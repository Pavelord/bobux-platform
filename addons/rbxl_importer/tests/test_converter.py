"""Format regressions for Roblox binary and XML values (no asset downloads)."""
import importlib.util
import io
from pathlib import Path
import struct
import unittest

spec = importlib.util.spec_from_file_location("converter", Path(__file__).parents[1] / "rbxl_converter.py")
converter = importlib.util.module_from_spec(spec)
spec.loader.exec_module(converter)

def interleave(values, width=4):
    rows = [v.to_bytes(width, "big") for v in values]
    return bytes(row[column] for column in range(width) for row in rows)

def string(value):
    raw = value.encode()
    return struct.pack("<I", len(raw)) + raw

class ConverterTests(unittest.TestCase):
    def test_binary_string_wire_type_is_lossless(self):
        raw = b"CSGPHS\x00\xff\xfe\x80" + bytes(range(256))
        payload = struct.pack("<I", len(raw)) + raw
        encoded = converter.parse_prop_values(io.BytesIO(payload), 0x01, 1, [])[0]
        self.assertEqual(converter.base64.b64decode(encoded["__bobux_binary_base64"]), raw)
        # Large binary values must survive the JSON sanitizer as well.
        large = {"__bobux_binary_base64": encoded["__bobux_binary_base64"] * 10000}
        self.assertEqual(converter.sanitize_for_strict_json(large, []), large)
        self.assertEqual(converter.parse_prop_values(io.BytesIO(string("local x = 1\n")), 0x01, 1, []), ["local x = 1\n"])

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
