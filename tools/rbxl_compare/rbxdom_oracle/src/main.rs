use std::collections::HashMap;
use std::fs::File;
use std::io::{BufReader, BufWriter, Read, Seek, SeekFrom, Write};
use std::path::Path;

use base64::{engine::general_purpose::STANDARD, Engine as _};
use flate2::write::GzEncoder;
use flate2::Compression;
use rbx_dom_weak::{types::{Ref, Variant}, WeakDom};
use serde_json::{json, Map, Value};
use sha2::{Digest, Sha256};

const MAX_INLINE_SERIALIZED_PROPERTY_BYTES: usize = 64 * 1024;

fn decode_place(path: &Path) -> Result<(WeakDom, &'static str), Box<dyn std::error::Error>> {
    let mut file = BufReader::new(File::open(path)?);
    let mut probe = [0_u8; 256];
    let read = file.read(&mut probe)?;
    file.seek(SeekFrom::Start(0))?;
    let bytes = &probe[..read];
    let trimmed = bytes
        .strip_prefix(&[0xEF, 0xBB, 0xBF])
        .unwrap_or(bytes)
        .iter()
        .copied()
        .skip_while(u8::is_ascii_whitespace)
        .collect::<Vec<_>>();
    if !trimmed.starts_with(b"<roblox!")
        && (trimmed.starts_with(b"<?xml") || trimmed.starts_with(b"<roblox") || trimmed.starts_with(b"<!--"))
    {
        let options = rbx_xml::DecodeOptions::new()
            .property_behavior(rbx_xml::DecodePropertyBehavior::ReadUnknown);
        Ok((rbx_xml::from_reader(file, options)?, "xml"))
    } else {
        Ok((rbx_binary::from_reader(file)?, "binary"))
    }
}

fn sha256_hex(bytes: &[u8]) -> String {
    let mut hasher = Sha256::new();
    hasher.update(bytes);
    format!("{:x}", hasher.finalize())
}

fn encode_large_binary(encoded: &Value) -> Option<Value> {
    let object = encoded.as_object()?;
    if object.len() != 1 {
        return None;
    }
    let (variant, payload) = object.iter().next()?;
    if variant != "BinaryString" && variant != "SharedString" {
        return None;
    }
    let base64 = payload.as_str()?;
    let bytes = STANDARD.decode(base64).ok()?;
    Some(json!({
        "__rbxdom_binary_sha256": sha256_hex(&bytes),
        "byte_length": bytes.len(),
        "variant": variant,
    }))
}

fn encode_property(value: &Variant, ref_to_id: &HashMap<Ref, usize>) -> Value {
    if let Variant::Ref(target) = value {
        return json!({
            "__rbxdom_ref_target_id": ref_to_id.get(target).copied(),
        });
    }
    if let Variant::Float32(number) = value {
        if !number.is_finite() {
            return json!({"__roblox_non_finite_number": if number.is_nan() { "NaN" } else if number.is_sign_positive() { "+Inf" } else { "-Inf" }});
        }
    }
    if let Variant::Float64(number) = value {
        if !number.is_finite() {
            return json!({"__roblox_non_finite_number": if number.is_nan() { "NaN" } else if number.is_sign_positive() { "+Inf" } else { "-Inf" }});
        }
    }
    if let Variant::String(text) = value {
        if text.len() > MAX_INLINE_SERIALIZED_PROPERTY_BYTES {
            return json!({
                "__rbxdom_digest": sha256_hex(text.as_bytes()),
                "__rbxdom_serialized_bytes": text.len(),
                "__rbxdom_variant": format!("{:?}", value.ty()),
            });
        }
    }

    let encoded = match serde_json::to_value(value) {
        Ok(encoded) => encoded,
        Err(error) => return json!({ "__rbxdom_serde_error": error.to_string() }),
    };
    if let Some(binary) = encode_large_binary(&encoded) {
        return binary;
    }
    let encoded_bytes = match serde_json::to_vec(&encoded) {
        Ok(bytes) => bytes,
        Err(error) => return json!({ "__rbxdom_serde_error": error.to_string() }),
    };
    if encoded_bytes.len() > MAX_INLINE_SERIALIZED_PROPERTY_BYTES {
        if matches!(value, Variant::String(_)) {
            return encoded;
        }
        return json!({
            "__rbxdom_digest": sha256_hex(&encoded_bytes),
            "__rbxdom_serialized_bytes": encoded_bytes.len(),
            "__rbxdom_variant": format!("{:?}", value.ty()),
        });
    }
    encoded
}

fn run(input: &Path, output: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let (dom, format) = decode_place(input)?;
    let root = dom.root_ref();

    // Assign stable breadth-first IDs. Instance order in the DOM is preserved
    // among siblings, while identity paths also retain class/name duplicates.
    let mut refs = vec![root];
    let mut parent_ids: Vec<Option<usize>> = vec![None];
    let mut identities: Vec<Vec<(String, String, usize)>> = vec![Vec::new()];
    let mut ref_to_id: HashMap<Ref, usize> = HashMap::new();
    ref_to_id.insert(root, 0);
    let mut cursor = 0;
    while cursor < refs.len() {
        let current_ref = refs[cursor];
        let current = dom.get_by_ref(current_ref).ok_or("DOM traversal lost an instance")?;
        let mut duplicate_ordinals: HashMap<(String, String), usize> = HashMap::new();
        for child_ref in current.children() {
            let child = dom.get_by_ref(*child_ref).ok_or("DOM child reference is invalid")?;
            let class = child.class.to_string();
            let name = child.name.clone();
            let ordinal = duplicate_ordinals
                .entry((class.clone(), name.clone()))
                .or_insert(0);
            let child_ordinal = *ordinal;
            *ordinal += 1;

            let child_id = refs.len();
            let mut child_identity = identities[cursor].clone();
            child_identity.push((class, name, child_ordinal));
            refs.push(*child_ref);
            parent_ids.push(Some(cursor));
            identities.push(child_identity);
            ref_to_id.insert(*child_ref, child_id);
        }
        cursor += 1;
    }

    let output_file = BufWriter::new(File::create(output)?);
    let mut gzip = GzEncoder::new(output_file, Compression::fast());
    let header = json!({
        "record": "header",
        "schema": 1,
        "format": format,
        "parser": "rojo-rbx/rbx-dom",
        "rbx_binary": "3.0.1",
        "rbx_xml": "3.0.0",
        "rbx_dom_weak": "4.2.0",
        "input_bytes": std::fs::metadata(input)?.len(),
        "instance_count": refs.len(),
    });
    serde_json::to_writer(&mut gzip, &header)?;
    gzip.write_all(b"\n")?;

    let mut class_counts: HashMap<String, usize> = HashMap::new();
    let mut property_count: usize = 0;
    for (index, instance_ref) in refs.iter().enumerate() {
        let instance = dom.get_by_ref(*instance_ref).ok_or("DOM traversal lost an instance")?;
        let class = instance.class.to_string();
        *class_counts.entry(class.clone()).or_insert(0) += 1;
        let mut properties = Map::with_capacity(instance.properties.len());
        for (name, value) in &instance.properties {
            property_count += 1;
            properties.insert(name.to_string(), encode_property(value, &ref_to_id));
        }
        let identity = identities[index]
            .iter()
            .map(|(segment_class, segment_name, ordinal)| {
                json!([segment_class, segment_name, ordinal])
            })
            .collect::<Vec<_>>();
        let parent_id = parent_ids[index].and_then(|parent| ref_to_id.get(&refs[parent]).copied());
        let record = json!({
            "record": "instance",
            "id": index,
            "parent_id": parent_id,
            "class": class,
            "name": instance.name,
            "identity": identity,
            "properties": properties,
        });
        serde_json::to_writer(&mut gzip, &record)?;
        gzip.write_all(b"\n")?;
    }

    let footer = json!({
        "record": "footer",
        "instance_count": refs.len(),
        "property_count": property_count,
        "class_counts": class_counts,
    });
    serde_json::to_writer(&mut gzip, &footer)?;
    gzip.write_all(b"\n")?;
    gzip.finish()?.flush()?;
    Ok(())
}

fn main() {
    let args = std::env::args_os().skip(1).collect::<Vec<_>>();
    if args.len() != 2 {
        eprintln!("Usage: rbxdom_place_oracle <input.rbxl|input.rbxlx> <output.jsonl.gz>");
        std::process::exit(2);
    }
    let input = Path::new(&args[0]);
    let output = Path::new(&args[1]);
    if let Err(error) = run(input, output) {
        eprintln!("rbx-dom oracle failed for {}: {error}", input.display());
        std::process::exit(1);
    }
}
