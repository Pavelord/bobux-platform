"""Format regressions for Roblox binary and XML values (no asset downloads)."""
import importlib.util
import io
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location("converter", Path(__file__).parents[1] / "rbxl_converter_v2.py")
converter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(converter)

def interleave(values, width=4):
    rows = [v.to_bytes(width, "big") for v in values]
    return bytes(row[column] for column in range(width) for row in rows)

def string(value):
    raw = value.encode()
    return struct.pack("<I", len(raw)) + raw

class ConverterTests(unittest.TestCase):
    def test_instance_tags_are_decoded_as_nul_delimited_utf8(self):
        raw = b"CollectionService\x00SpawnPoint\x00\xff"
        value = converter.decode_instance_tags(raw)
        self.assertEqual(value, ["CollectionService", "SpawnPoint", "\ufffd"])
        encoded = {"__bobux_binary_base64": converter.base64.b64encode(raw).decode("ascii")}
        self.assertEqual(converter.decode_instance_tags(encoded), value)

    def test_non_finite_numbers_use_strict_json_markers(self):
        warnings = []
        value = converter.sanitize_for_strict_json({"values": [float("nan"), float("inf"), float("-inf")]}, warnings)
        self.assertEqual(value, {"values": [
            {"__roblox_non_finite_number": "nan"},
            {"__roblox_non_finite_number": "+inf"},
            {"__roblox_non_finite_number": "-inf"},
        ]})
        converter.json.dumps(value, allow_nan=False)

    def test_xml_tags_binary_string_becomes_array(self):
        encoded = converter.base64.b64encode(b"SpawnPoint\x00Checkpoint").decode("ascii")
        value = converter.parse_rbxlx(f'''<roblox><Item class="Part" referent="RBX1"><Properties>
        <BinaryString name="Tags">{encoded}</BinaryString>
        </Properties></Item></roblox>''')
        props = value["instances"]["1"]["properties"]
        self.assertEqual(props["Tags"], ["SpawnPoint", "Checkpoint"])

    def test_xml_reflection_migrations_keep_legacy_fields_and_add_current_names(self):
        value = converter.parse_rbxlx('''<roblox><Item class="ScreenGui" referent="RBX1"><Properties>
        <bool name="IgnoreGuiInset">false</bool>
        </Properties></Item><Item class="Decal" referent="RBX2"><Properties>
        <string name="Texture">rbxassetid://123456789</string>
        <string name="MetalnessMap"></string>
        </Properties></Item><Item class="ShirtGraphic" referent="RBX3"><Properties>
        <string name="Graphic">rbxassetid://987654321</string>
        </Properties></Item></roblox>''')
        screen = value["instances"]["1"]["properties"]
        decal = value["instances"]["2"]["properties"]
        shirt_graphic = value["instances"]["3"]["properties"]
        self.assertEqual(screen["IgnoreGuiInset"], False)
        self.assertEqual(screen["ScreenInsets"], 2)
        self.assertEqual(decal["Texture"], "rbxassetid://123456789")
        self.assertEqual(decal["TextureContent"], "rbxassetid://123456789")
        self.assertEqual(decal["MetalnessMapContent"], "")
        self.assertEqual(shirt_graphic["TextureContent"], "rbxassetid://987654321")
        self.assertEqual(value["property_migrations"]["ScreenGui.IgnoreGuiInset->ScreenInsets"], 1)

    def test_explicit_current_screen_insets_are_not_overwritten(self):
        value = converter.apply_reflection_property_migrations({"instances": {
            "1": {"class": "ScreenGui", "properties": {"IgnoreGuiInset": True, "ScreenInsets": 3}}
        }})
        props = value["instances"]["1"]["properties"]
        self.assertEqual(props["ScreenInsets"], 3)
        self.assertNotIn("property_migrations", value)

    def test_current_texture_content_aliases_are_collected_for_asset_fetch(self):
        result = {"instances": {
            "1": {"class": "Decal", "properties": {"NormalMapContent": "rbxassetid://1234567890"}},
            "2": {"class": "ShirtGraphic", "properties": {"TextureContent": "rbxassetid://9876543210"}},
        }}
        self.assertEqual(
            set(converter._collect_exact_texture_asset_ids(result)),
            {"1234567890", "9876543210"},
        )

    def test_attributes_serialize_decodes_and_keeps_original_bytes(self):
        raw = struct.pack('<I', 2)
        raw += string("Kills") + b'\x04' + struct.pack('<i', 7)
        raw += string("PlayerName") + b'\x02' + string("Builder")
        value = converter.decode_attributes_serialize({
            "__bobux_binary_base64": converter.base64.b64encode(raw).decode("ascii")
        })
        self.assertEqual(value, {"Kills": 7, "PlayerName": "Builder"})

    def test_xml_attributes_are_exposed_as_runtime_attributes(self):
        raw = struct.pack('<I', 1) + string("Version") + b'\x02' + string("2.5")
        encoded = converter.base64.b64encode(raw).decode("ascii")
        value = converter.parse_rbxlx(f'''<roblox version="4"><Item class="Folder" referent="RBX1"><Properties>
        <BinaryString name="AttributesSerialize">{encoded}</BinaryString>
        </Properties></Item></roblox>''')
        props = value["instances"]["1"]["properties"]
        self.assertEqual(props["Attributes"], {"Version": "2.5"})
        self.assertIn("__bobux_binary_base64", props["AttributesSerialize"])

    def test_material_colors_decode_preserves_all_palette_entries(self):
        raw = bytes(6) + bytes(range(1, 64))
        colors = converter.decode_material_colors({
            "__bobux_binary_base64": converter.base64.b64encode(raw).decode("ascii")
        })
        self.assertEqual(len(colors), 21)
        self.assertEqual(colors["Grass"], [1, 2, 3])
        self.assertEqual(colors["Pavement"], [61, 62, 63])

    def test_binary_string_wire_type_is_lossless(self):
        raw = b"CSGPHS\x00\xff\xfe\x80" + bytes(range(256))
        payload = struct.pack("<I", len(raw)) + raw
        encoded = converter.parse_prop_values(io.BytesIO(payload), 0x01, 1, [])[0]
        self.assertEqual(converter.base64.b64decode(encoded["__bobux_binary_base64"]), raw)
        # Large binary values must survive the JSON sanitizer as well.
        large = {"__bobux_binary_base64": encoded["__bobux_binary_base64"] * 10000}
        self.assertEqual(converter.sanitize_for_strict_json(large, []), large)
        self.assertEqual(converter.parse_prop_values(io.BytesIO(string("local x = 1\n")), 0x01, 1, []), ["local x = 1\n"])

    def test_binary_instance_name_uses_utf8_lossy_text_not_blob_marker(self):
        raw = b"Hello \xe5m Your New Lord Lolz"
        marker = {"__bobux_binary_base64": converter.base64.b64encode(raw).decode("ascii")}
        self.assertEqual(converter.decode_instance_name(marker), "Hello \ufffdm Your New Lord Lolz")
        self.assertEqual(converter.decode_text_property(marker), "Hello \ufffdm Your New Lord Lolz")

    def test_opaque_referents_and_forward_references(self):
        value = converter.parse_rbxlx('''<roblox version="4">
        <Item class="Model" referent="RBXabcdef1"><Properties><Ref name="PrimaryPart">RBXfedcba1</Ref></Properties>
        <Item class="Part" referent="RBXfedcba1"><Properties><string name="Name">Head</string></Properties></Item></Item>
        <Item class="Part" referent="RBX1"><Properties><string name="Name">Numeric</string></Properties></Item></roblox>''')
        instances = value["instances"]
        self.assertEqual(len(instances), 3)
        model = next(v for v in instances.values() if v["class"] == "Model")
        part = instances[str(model["properties"]["PrimaryPart"])]
        self.assertEqual(part["properties"]["Name"], "Head")

    def test_xml_color_and_source_are_preserved(self):
        value = converter.parse_rbxlx('''<roblox><Item class="Script" referent="source"><Properties>
        <Color3uint8 name="Color">4281558681</Color3uint8>
        <ProtectedString name="Source"><![CDATA[  local text = "a & b"\nreturn text  ]]></ProtectedString>
        </Properties></Item></roblox>''')
        props = next(iter(value["instances"].values()))["properties"]
        self.assertEqual(props["Color"], [0x33 / 255, 0x66 / 255, 0x99 / 255])
        self.assertEqual(props["Source"], '  local text = "a & b"\nreturn text  ')

    def test_duplicate_referents_report_failure(self):
        with self.assertRaises(ValueError):
            converter.parse_rbxlx('<roblox><Item referent="same"/><Item referent="same"/></roblox>')

    def test_brickcolor_unsigned(self):
        self.assertEqual(converter.parse_prop_values(io.BytesIO(interleave([194, 1004])), 0x0B, 2, []), [194, 1004])

    def test_optional_cframe_consumes_boolean_trailer(self):
        payload = b'\x10\x02\x02' + bytes(24) + b'\x02\x01\x00'
        result = converter.parse_prop_values(io.BytesIO(payload), 0x1E, 2, [])
        self.assertEqual([r["present"] for r in result], [True, False])
        self.assertEqual(result[0]["cframe"]["position"], [0, 0, 0])

    def test_font_records_are_sequential(self):
        payload = string("first") + struct.pack('<HB', 400, 0) + string("cache1")
        payload += string("second") + struct.pack('<HB', 700, 1) + string("cache2")
        result = converter.parse_prop_values(io.BytesIO(payload), 0x20, 2, [])
        self.assertEqual([r["family"] for r in result], ["first", "second"])
        self.assertEqual([r["weight"] for r in result], [400, 700])

    def test_truncated_string_is_not_silently_accepted(self):
        with self.assertRaises(EOFError):
            converter.read_roblox_string(io.BytesIO(struct.pack('<I', 20) + b'abc'))

if __name__ == "__main__":
    unittest.main()
