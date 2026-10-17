"""Narrow, explicit repairs for legacy XML maps used only by external oracles."""

from __future__ import annotations

from pathlib import Path
import re


BARE_XML_AMPERSAND = re.compile(rb"&(?!#(?:[0-9]+|[xX][0-9A-Fa-f]+);|(?:amp|lt|gt|quot|apos);)")
LEGACY_EXTERNAL = re.compile(rb"<External\b[^>]*/>|<External\b[^>]*>.*?</External>", re.DOTALL)
XML_LITERAL_SECTIONS = re.compile(rb"(<!\[CDATA\[.*?\]\]>|<!--.*?-->)", re.DOTALL)


def is_legacy_xml(source: Path) -> bool:
	with source.open("rb") as stream:
		probe = stream.read(256).lstrip(b"\xef\xbb\xbf\r\n\t ")
	return not probe.startswith(b"<roblox!") and (
		probe.startswith(b"<?xml") or probe.startswith(b"<roblox") or probe.startswith(b"<!--")
	)


def sanitize_legacy_xml(source: Path, destination: Path) -> dict[str, int]:
	data = source.read_bytes()
	data, external_count = LEGACY_EXTERNAL.subn(b"", data)
	sections = XML_LITERAL_SECTIONS.split(data)
	ampersand_count = 0
	for index in range(0, len(sections), 2):
		sections[index], count = BARE_XML_AMPERSAND.subn(b"&amp;", sections[index])
		ampersand_count += count
	destination.parent.mkdir(parents=True, exist_ok=True)
	destination.write_bytes(b"".join(sections))
	return {
		"removed_legacy_external_elements": external_count,
		"escaped_bare_ampersands": ampersand_count,
	}
