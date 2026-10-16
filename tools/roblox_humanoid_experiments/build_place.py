"""Build a separate XML place using only our scripts and public Roblox classes."""
from pathlib import Path
import xml.etree.ElementTree as ET

HERE = Path(__file__).resolve().parent


def item(parent, class_name, referent, name):
    node = ET.SubElement(parent, "Item", {"class": class_name, "referent": referent})
    props = ET.SubElement(node, "Properties")
    ET.SubElement(props, "string", {"name": "Name"}).text = name
    return node, props


def vector(props, name, xyz):
    node = ET.SubElement(props, "Vector3", {"name": name})
    for component, value in zip("XYZ", xyz):
        ET.SubElement(node, component).text = str(value)


def cf(props, name, xyz):
    node = ET.SubElement(props, "CoordinateFrame", {"name": name})
    for component, value in zip("XYZ", xyz):
        ET.SubElement(node, component).text = str(value)
    for r in range(3):
        for c in range(3):
            ET.SubElement(node, f"R{r}{c}").text = "1" if r == c else "0"


def build(output: Path | None = None):
    document = ET.Element("roblox", {"version": "4"})
    ET.SubElement(document, "External").text = "null"
    ET.SubElement(document, "External").text = "nil"
    workspace, props = item(document, "Workspace", "WORKSPACE", "Workspace")
    ET.SubElement(props, "float", {"name": "Gravity"}).text = "196.2"
    _, base_props = item(workspace, "Part", "BASEPLATE", "Baseplate")
    ET.SubElement(base_props, "bool", {"name": "Anchored"}).text = "true"
    ET.SubElement(base_props, "bool", {"name": "CanCollide"}).text = "true"
    vector(base_props, "size", (280, 1, 280))
    cf(base_props, "CFrame", (0, -0.5, 0))
    ET.SubElement(base_props, "token", {"name": "TopSurface"}).text = "0"
    ET.SubElement(base_props, "token", {"name": "BottomSurface"}).text = "0"
    item(document, "Players", "PLAYERS", "Players")
    item(document, "ReplicatedStorage", "REPLICATED", "ReplicatedStorage")
    server, _ = item(document, "ServerScriptService", "SERVERSCRIPTS", "ServerScriptService")
    _, setup_props = item(server, "Script", "SETUP", "HumanoidExperimentSetup")
    ET.SubElement(setup_props, "ProtectedString", {"name": "Source"}).text = (HERE / "setup.server.luau").read_text(encoding="utf-8")
    starter, _ = item(document, "StarterPlayer", "STARTERPLAYER", "StarterPlayer")
    scripts, _ = item(starter, "StarterPlayerScripts", "STARTERSCRIPTS", "StarterPlayerScripts")
    _, measure_props = item(scripts, "LocalScript", "MEASURE", "HumanoidBlackBoxMeasurement")
    ET.SubElement(measure_props, "ProtectedString", {"name": "Source"}).text = (HERE / "measure.client.luau").read_text(encoding="utf-8")
    tree = ET.ElementTree(document)
    ET.indent(tree, space="  ")
    output = output or HERE / "HumanoidBlackBox.rbxlx"
    tree.write(output, encoding="utf-8", xml_declaration=True)
    print(output)
    print(f"XML place written: {output.stat().st_size} bytes")
    return output


if __name__ == "__main__":
    build()
