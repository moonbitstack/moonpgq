"""Turn the openCypher TCK feature files into MoonBit data the conformance
package replays.

The input is the `tck/features` tree of the openCypher repository, vendored
under `scripts/conformance/opencypher/features`. The output is
`src/conformance/cypher_cases_test.mbt`: one case per scenario, carrying the
`CREATE` statements that build the fixture, the query, and the table the query
must return.

Usage: python3 scripts/gen_cypher_cases.py [--check] [--report]
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FEATURES = ROOT / "scripts" / "conformance" / "opencypher" / "features"
OUTPUT = ROOT / "src" / "conformance" / "cypher_cases_test.mbt"
CASES_PER_FUNCTION = 80

STEP_KEYWORD = re.compile(r"^\s*(Given|And|But|When|Then)\s+(.*)$")
TAG = re.compile(r"^\s*(@[\w:]+(?:\s+@[\w:]+)*)\s*$")
SCENARIO = re.compile(r"^\s*Scenario(?:\s+Outline)?:\s*(.*)$")


class Scenario:
    def __init__(self, path, name):
        self.path = path
        self.name = name
        self.setup = []
        self.query = None
        self.columns = []
        self.rows = []
        self.in_order = False
        self.loose_lists = False
        self.empty = False
        self.raises = False
        self.unsupported = None

    def fail(self, reason):
        if self.unsupported is None:
            self.unsupported = reason


def parse_features():
    scenarios = []
    for path in sorted(FEATURES.rglob("*.feature")):
        relative = path.relative_to(FEATURES).as_posix()
        lines = path.read_text(encoding="utf-8").splitlines()
        current = None
        index = 0
        while index < len(lines):
            line = lines[index]
            if TAG.match(line) or line.strip().startswith("Feature:"):
                index += 1
                continue
            match = SCENARIO.match(line)
            if match:
                current = Scenario(relative, match.group(1).strip())
                scenarios.append(current)
                index += 1
                continue
            step = STEP_KEYWORD.match(line)
            if step and current is not None:
                keyword, text = step.group(1), step.group(2).rstrip()
                docstring = None
                table = []
                index += 1
                while index < len(lines) and lines[index].strip() == '"""':
                    index += 1
                    body = []
                    while index < len(lines) and lines[index].strip() != '"""':
                        body.append(lines[index].strip())
                        index += 1
                    index += 1
                    docstring = "\n".join(body)
                while index < len(lines) and lines[index].strip().startswith("|"):
                    cells = [
                        cell.strip()
                        for cell in lines[index].strip().strip("|").split("|")
                    ]
                    table.append(cells)
                    index += 1
                apply_step(current, keyword, text, docstring, table)
                continue
            index += 1
    return scenarios


def apply_step(scenario, keyword, text, docstring, table):
    text = text.rstrip(":")
    if text in ("an empty graph", "any graph", "the empty graph"):
        return
    if text == "having executed":
        if docstring:
            scenario.setup.append(docstring)
        return
    if text == "executing query":
        scenario.query = docstring
        return
    if text.startswith("the result should be, in any order"):
        take_table(scenario, table, ordered=False)
        return
    if text.startswith("the result should be, in order"):
        take_table(scenario, table, ordered=True)
        return
    if text.startswith("the result should be (ignoring element order for lists)"):
        take_table(scenario, table, ordered=True)
        scenario.loose_lists = True
        return
    if text == "the result should be empty":
        scenario.empty = True
        return
    if text == "no side effects":
        return
    if text.startswith("a SyntaxError should be raised") or text.startswith(
        "a TypeError should be raised"
    ) or text.startswith("an ArgumentError should be raised"):
        scenario.raises = True
        return
    if text == "parameters are":
        scenario.fail("the scenario passes parameters")
        return
    if text.startswith("the result should be"):
        scenario.fail(f"assertion not understood: {text}")
        return
    scenario.fail(f"step not understood: {text}")


def take_table(scenario, table, ordered):
    if len(table) < 1:
        scenario.fail("the table has no header")
        return
    scenario.columns = table[0]
    scenario.rows = table[1:]
    scenario.in_order = ordered


def moonbit_string(text):
    out = []
    for char in text:
        if char == "\\":
            out.append("\\\\")
        elif char == '"':
            out.append('\\"')
        elif char == "\n":
            out.append("\\n")
        elif char == "\t":
            out.append("\\t")
        elif char == "\r":
            continue
        else:
            out.append(char)
    return '"' + "".join(out) + '"'


def moonbit_cells(cells):
    return "[" + ", ".join(moonbit_string(cell) for cell in cells) + "]"


def render(scenarios):
    lines = []
    lines.append("// Copyright 2026 Leo Cheng")
    lines.append("// SPDX-License-Identifier: Apache-2.0")
    lines.append("")
    lines.append("// Generated by scripts/gen_cypher_cases.py from the openCypher TCK,")
    lines.append("// vendored under scripts/conformance/opencypher/features. Do not edit.")
    lines.append("")
    lines.append("///|")
    lines.append("/// One scenario of the TCK: the statements that build its graph, the query,")
    lines.append("/// and the table the query has to return.")
    lines.append("struct CypherCase {")
    lines.append("  file : String")
    lines.append("  scenario : String")
    lines.append("  setup : Array[String]")
    lines.append("  query : String")
    lines.append("  columns : Array[String]")
    lines.append("  rows : Array[Array[String]]")
    lines.append("  in_order : Bool")
    lines.append("  expectation : CypherExpectation")
    lines.append("}")
    lines.append("")
    lines.append("///|")
    lines.append("enum CypherExpectation {")
    lines.append("  Table")
    lines.append("  Raises")
    lines.append("  Unsupported(String)")
    lines.append("}")
    lines.append("")

    blocks = [
        scenarios[index : index + CASES_PER_FUNCTION]
        for index in range(0, len(scenarios), CASES_PER_FUNCTION)
    ]
    for number, block in enumerate(blocks):
        lines.append("///|")
        lines.append(f"fn cypher_cases_{number:02d}() -> Array[CypherCase] {{")
        lines.append("  [")
        for scenario in block:
            lines.append("    {")
            lines.append(f"      file: {moonbit_string(scenario.path)},")
            lines.append(f"      scenario: {moonbit_string(scenario.name)},")
            setup = "[" + ", ".join(moonbit_string(text) for text in scenario.setup) + "]"
            lines.append(f"      setup: {setup},")
            lines.append(f"      query: {moonbit_string(scenario.query or '')},")
            lines.append(f"      columns: {moonbit_cells(scenario.columns)},")
            rows = (
                "["
                + ", ".join(moonbit_cells(row) for row in scenario.rows)
                + "]"
            )
            lines.append(f"      rows: {rows},")
            lines.append(f"      in_order: {str(scenario.in_order).lower()},")
            lines.append(f"      expectation: {render_expectation(scenario)},")
            lines.append("    },")
        lines.append("  ]")
        lines.append("}")
        lines.append("")

    lines.append("///|")
    lines.append("fn all_cypher_cases() -> Array[CypherCase] {")
    lines.append("  let cases : Array[CypherCase] = []")
    for number in range(len(blocks)):
        lines.append(f"  cases.append(cypher_cases_{number:02d}())")
    lines.append("  cases")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def render_expectation(scenario):
    if scenario.unsupported is not None:
        return f"Unsupported({moonbit_string(scenario.unsupported)})"
    if scenario.raises:
        return "Raises"
    if scenario.query is None:
        return f'Unsupported("no query")'
    return "Table"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--report", action="store_true")
    options = parser.parse_args()

    scenarios = parse_features()
    rendered = render(scenarios)
    if options.check:
        current = OUTPUT.read_text(encoding="utf-8") if OUTPUT.exists() else ""
        if current != rendered:
            print(f"{OUTPUT} is out of date; run scripts/gen_cypher_cases.py")
            return 1
        print(f"{OUTPUT} is up to date ({len(scenarios)} scenarios)")
        return 0
    OUTPUT.write_text(rendered, encoding="utf-8", newline="\n")
    supported = sum(1 for scenario in scenarios if scenario.unsupported is None)
    print(
        f"wrote {len(scenarios)} scenarios ({supported} supported, "
        f"{len(scenarios) - supported} unsupported)"
    )
    if options.report:
        reasons = {}
        for scenario in scenarios:
            if scenario.unsupported:
                reasons[scenario.unsupported] = reasons.get(scenario.unsupported, 0) + 1
        for reason, count in sorted(reasons.items(), key=lambda item: -item[1]):
            print(f"{count:5d}  {reason}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
