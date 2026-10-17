import unittest

from tools.rbxl_compare import compare_one


class ComparisonNormalizationTests(unittest.TestCase):
    def test_unique_id_hex_matches_decoded_binary_components(self):
        expected = {
            "epoch": 0x0818BFF4,
            "index": 0x388,
            "random": 0x121F64BAA599BBB9,
        }
        self.assertEqual(compare_one._canon_unique_id("121f64baa599bbb90818bff400000388"), expected)
        self.assertEqual(
            compare_one._canon_bobux(expected, "UniqueId", {}, {}),
            expected,
        )

    def test_object_value_is_reference_but_int_value_is_numeric(self):
        references = {"17": (("Workspace", "Workspace", 0), ("Part", "Part", 0))}
        self.assertEqual(compare_one._canon_bobux(17, "Value", {}, references, "IntValue"), 17)
        self.assertEqual(
            compare_one._canon_bobux(17, "Value", {}, references, "ObjectValue"),
            {"__ref_target": references["17"]},
        )

    def test_rect_and_old_uicorner_values_normalize_to_current_shape(self):
        legacy = {"min": {"x": 1, "y": 2}, "max": {"x": 3, "y": 4}}
        expected_rect = {"min": [1, 2], "max": [3, 4]}
        self.assertEqual(compare_one._canon_bobux(legacy, "SliceCenter", {}, {}), expected_rect)
        self.assertEqual(compare_one._canonical_properties("UICorner", {"CornerRadius": {"scale": 0, "offset": 6}}, "bobux"), {
            "bottomleftradius": ("CornerRadius", {"scale": 0, "offset": 6}),
            "bottomrightradius": ("CornerRadius", {"scale": 0, "offset": 6}),
            "topleftradius": ("CornerRadius", {"scale": 0, "offset": 6}),
            "toprightradius": ("CornerRadius", {"scale": 0, "offset": 6}),
        })

    def test_nan_in_nested_vector_matches_dom_null_representation(self):
        nan = {"__non_finite": "NaN"}
        self.assertTrue(compare_one._equal([nan, nan, nan], [None, None, None]))
        self.assertTrue(compare_one._equal({"__non_finite": "+Inf"}, None))

    def test_stable_unique_id_fallback_ignores_zero_id(self):
        props = {"UniqueId": {"epoch": 3, "index": 9, "random": 12}}
        self.assertEqual(compare_one._unique_id_key(props, "bobux"), (3, 9, 12))
        self.assertEqual(compare_one._unique_id_key({"UniqueId": {"epoch": 0, "index": 0, "random": 0}}, "bobux"), None)

    def test_legacy_character_mesh_asset_ids_match_content_uris(self):
        self.assertEqual(compare_one._canon_bobux(376169183, "MeshId", {}, {}, "CharacterMesh"), "rbxassetid://376169183")
        self.assertEqual(compare_one._canon_bobux(0, "BaseTextureId", {}, {}, "CharacterMesh"), "")

    def test_original_script_guid_shared_binary_is_decoded_as_text(self):
        guid = "{F8287CA0-7342-440B-870E-1D7B29F5429C}"
        encoded = compare_one.base64.b64encode(guid.encode("ascii")).decode("ascii")
        self.assertEqual(compare_one._canon_dom_property({"BinaryString": encoded}, "OriginalScriptGuid", {}), guid)

    def test_utf8_text_binary_field_is_hashed_as_its_original_bytes(self):
        self.assertEqual(compare_one._canon_bobux("[]", "AccessoryRigidAndLayeredBlob", {}, {}), compare_one._hash_bytes(b"[]"))
        guid = "{F8287CA0-7342-440B-870E-1D7B29F5429C}"
        self.assertEqual(compare_one._canon_bobux(guid, "OriginalScriptGuid", {}, {}), compare_one._hash_bytes(guid.encode("utf-8")))
        self.assertEqual(compare_one._canon_bobux("", "LODData", {}, {}), compare_one._hash_bytes(b""))

    def test_decal_and_texture_legacy_material_maps_match_content_properties(self):
        for class_name in ("Decal", "Texture"):
            for legacy_name, content_name in (
                ("MetalnessMap", "MetalnessMapContent"),
                ("NormalMap", "NormalMapContent"),
                ("RoughnessMap", "RoughnessMapContent"),
            ):
                left = compare_one._canonical_properties(class_name, {legacy_name: ""}, "bobux")
                right = compare_one._canonical_properties(class_name, {content_name: {"Content": "None"}}, "rbx_dom")
                canonical_name = legacy_name.casefold() + "content"
                self.assertIn(canonical_name, left)
                self.assertIn(canonical_name, right)
                self.assertEqual(
                    compare_one._canon_bobux(left[canonical_name][1], legacy_name, {}, {}, class_name),
                    compare_one._canon_dom(right[canonical_name][1], {}),
                )

    def test_shirt_graphic_legacy_uri_matches_texture_content(self):
        uri = "rbxassetid://123456789"
        left = compare_one._canonical_properties("ShirtGraphic", {"Graphic": uri}, "bobux")
        right = compare_one._canonical_properties("ShirtGraphic", {"TextureContent": {"Content": {"Uri": uri}}}, "rbx_dom")
        self.assertEqual(left["texturecontent"][1], right["texturecontent"][1]["Content"]["Uri"])

    def test_legacy_ignore_gui_inset_matches_screen_insets_enum(self):
        left = compare_one._canonical_properties("ScreenGui", {"IgnoreGuiInset": False}, "bobux")
        right = compare_one._canonical_properties("ScreenGui", {"ScreenInsets": {"Enum": 2}}, "rbx_dom")
        self.assertEqual(left["screeninsets"][0], "IgnoreGuiInset")
        self.assertEqual(right["screeninsets"][0], "ScreenInsets")
        self.assertEqual(compare_one._canon_bobux(False, "IgnoreGuiInset", {}, {}, "ScreenGui"), 2)
        self.assertEqual(compare_one._canon_bobux(True, "IgnoreGuiInset", {}, {}, "ScreenGui"), 1)
        self.assertEqual(compare_one._canon_dom(right["screeninsets"][1], {}), 2)


if __name__ == "__main__":
    unittest.main()
