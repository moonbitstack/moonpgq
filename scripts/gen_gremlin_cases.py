"""Turn the Gherkin feature files of Apache TinkerPop's Gremlin test suite into
MoonBit data the conformance package replays.

The input is the `features/` tree of `gremlin-test`, vendored under
`scripts/conformance/tinkerpop/features` at the revision the suite is pinned to.
The output is `src/conformance/feature_cases_test.mbt`, one `FeatureCase` per
scenario: the graph to build, the parameters the scenario binds, the traversal
text, and what the scenario expects.

A scenario that uses something the engine does not implement is still emitted,
with an `Unsupported` expectation and the reason, so that the report counts it
instead of silently dropping it.

Usage: python3 scripts/gen_gremlin_cases.py [--check]
"""

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FEATURES = ROOT / "scripts" / "conformance" / "tinkerpop" / "features"
OUTPUT = ROOT / "src" / "conformance" / "feature_cases_test.mbt"
CASES_PER_FUNCTION = 120

# Features whose behaviour the language does not pin down, or that need a
# capability this engine deliberately leaves out. A scenario carrying one of
# these tags is reported as unsupported rather than as a failure.
SKIPPED_TAGS = {
    "AllowNullPropertyValues": "null property values are not part of the store contract",
    "DataGeometry": "geometry values are not part of the value model",
    "MultiLabelDefault": "multi-label vertices are not part of the model",
    "WithReservedKeysVerificationStrategy": "reserved keys are a strategy, not a step",
    "StepWrite": "the scenario asserts on the graph after a write, not on the result",
}

STEP_KEYWORD = re.compile(r"^\s*(Given|And|But|When|Then)\s+(.*)$")
TAG = re.compile(r"^\s*(@[\w:]+(?:\s+@[\w:]+)*)\s*$")
SCENARIO = re.compile(r"^\s*Scenario(?:\s+Outline)?:\s*(.*)$")
PARAMETER = re.compile(r'^using the parameter (\w+) defined as "(.*)"$')
COUNT = re.compile(r"^the result should have a count of (\S+)$")


class Scenario:
    def __init__(self, path, name, tags):
        self.path = path
        self.name = name
        self.tags = tags
        self.graph = None
        self.parameters = []
        self.query = None
        self.expectation = ("Unsupported", "no assertion")
        self.unsupported = None

    def fail(self, reason):
        if self.unsupported is None:
            self.unsupported = reason


def parse_features():
    """One pass per file: tags and `Scenario:` open a case, steps fill it."""
    scenarios = []
    for path in sorted(FEATURES.rglob("*.feature")):
        relative = path.relative_to(FEATURES).as_posix()
        lines = path.read_text(encoding="utf-8").splitlines()
        tags = []
        current = None
        index = 0
        while index < len(lines):
            line = lines[index]
            if line.strip().startswith("Feature:"):
                tags = []
                index += 1
                continue
            tag_match = TAG.match(line)
            if tag_match:
                tags = [tag for tag in tag_match.group(1).split() if tag.startswith("@")]
                index += 1
                continue
            scenario_match = SCENARIO.match(line)
            if scenario_match:
                current = Scenario(relative, scenario_match.group(1).strip(), list(tags))
                for tag in current.tags:
                    name = tag.lstrip("@").split(":")[0]
                    if name in SKIPPED_TAGS:
                        current.fail(SKIPPED_TAGS[name])
                scenarios.append(current)
                tags = []
                index += 1
                continue
            step_match = STEP_KEYWORD.match(line)
            if step_match and current is not None:
                keyword, text = step_match.group(1), step_match.group(2).rstrip()
                docstring = None
                table = []
                index += 1
                while index < len(lines) and lines[index].strip() == '"""':
                    index += 1
                    body = []
                    while index < len(lines) and lines[index].strip() != '"""':
                        body.append(lines[index])
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


GRAPH_COUNT = re.compile(r'^the graph should return (\S+) for count of "(.*)"$')
RAISE_MESSAGE = re.compile(r"^the traversal will raise an error")


def apply_step(scenario, keyword, text, docstring, table):
    if "graph" in text and keyword == "Given":
        if "modern graph" in text:
            scenario.graph = "modern"
        elif "crew graph" in text:
            scenario.graph = "crew"
        elif "empty graph" in text:
            scenario.graph = "empty"
        else:
            scenario.fail(f"unknown graph: {text}")
        return
    match = PARAMETER.match(text)
    if match:
        scenario.parameters.append((match.group(1), match.group(2)))
        return
    if text in ("the traversal of", "the traversal"):
        scenario.query = docstring or ""
        return
    if text.startswith("the traversal of"):
        scenario.query = docstring or ""
        return
    if text == "the result should be unordered":
        scenario.expectation = ("Unordered", table_cells(table))
        return
    if text == "the result should be ordered":
        scenario.expectation = ("Ordered", table_cells(table))
        return
    if text == "the intent":
        return
    if text == "the result should be of":
        scenario.expectation = ("AnyOf", table_cells(table))
        return
    graph_count = GRAPH_COUNT.match(text)
    if graph_count:
        scenario.expectation = ("GraphCount", (graph_count.group(1), graph_count.group(2)))
        return
    if RAISE_MESSAGE.match(text):
        scenario.expectation = ("Raises", [])
        return
    if text.startswith("using the side effect"):
        scenario.fail("side effects cannot be passed as parameters")
        return
    if text == "the result should be empty":
        scenario.expectation = ("Empty", [])
        return
    count = COUNT.match(text)
    if count:
        scenario.expectation = ("Count", count.group(1))
        return
    if text.startswith("the traversal should raise an error"):
        scenario.expectation = ("Raises", [])
        return
    if text == "no side effects" or text == "the side effects should be":
        scenario.fail("side effects are asserted separately, not as a result")
        return
    if text.startswith("and the result should be"):
        return
    if text in ("iterated to list", "iterated next", "iterated"):
        return
    if keyword in ("When", "Then", "And", "But") and text.startswith("iterated"):
        return
    if text.startswith("the result should be a subgraph"):
        scenario.fail("subgraph results are not part of the value model")
        return
    if text.startswith("the result should have a tree structure"):
        scenario.fail("tree results are not implemented")
        return
    if text == "having executed":
        scenario.fail("scenario builds its graph with a traversal")
        return
    if text.startswith("the graph initializer"):
        scenario.fail("scenario builds its graph with a traversal")
        return
    scenario.fail(f"step not understood: {text}")


def table_cells(table):
    """The first data column of a Gherkin table, ignoring its header row."""
    if len(table) < 2:
        return []
    return [row[0] for row in table[1:]]


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


def moonbit_array(values, wrap):
    if not values:
        return "[]"
    inner = ", ".join(wrap(value) for value in values)
    return "[" + inner + "]"


def render(scenarios):
    lines = []
    lines.append("// Copyright 2026 Leo Cheng")
    lines.append("// SPDX-License-Identifier: Apache-2.0")
    lines.append("")
    lines.append("// Generated by scripts/gen_gremlin_cases.py from the Gherkin feature files")
    lines.append("// of Apache TinkerPop's gremlin-test, vendored under")
    lines.append("// scripts/conformance/tinkerpop/features. Do not edit by hand.")
    lines.append("")
    lines.append("///|")
    lines.append("/// One scenario of the feature suite: the graph, the parameters the scenario")
    lines.append("/// binds, the traversal, and what it expects.")
    lines.append("struct FeatureCase {")
    lines.append("  file : String")
    lines.append("  scenario : String")
    lines.append("  graph : String")
    lines.append("  parameters : Array[(String, String)]")
    lines.append("  query : String")
    lines.append("  expectation : Expectation")
    lines.append("}")
    lines.append("")
    lines.append("///|")
    lines.append("enum Expectation {")
    lines.append("  Unordered(Array[String])")
    lines.append("  Ordered(Array[String])")
    lines.append("  Count(Int64)")
    lines.append("  Empty")
    lines.append("  Raises")
    lines.append("  AnyOf(Array[String])")
    lines.append("  GraphCount(Int64, String)")
    lines.append("  Unsupported(String)")
    lines.append("}")
    lines.append("")

    blocks = [
        scenarios[index : index + CASES_PER_FUNCTION]
        for index in range(0, len(scenarios), CASES_PER_FUNCTION)
    ]
    for number, block in enumerate(blocks):
        lines.append("///|")
        lines.append(f"fn feature_cases_{number:02d}() -> Array[FeatureCase] {{")
        lines.append("  [")
        for scenario in block:
            lines.append("    {")
            lines.append(f"      file: {moonbit_string(scenario.path)},")
            lines.append(f"      scenario: {moonbit_string(scenario.name)},")
            graph = scenario.graph or "empty"
            lines.append(f"      graph: {moonbit_string(graph)},")
            parameters = moonbit_array(
                scenario.parameters,
                lambda pair: "("
                + moonbit_string(pair[0])
                + ", "
                + moonbit_string(pair[1])
                + ")",
            )
            lines.append(f"      parameters: {parameters},")
            lines.append(f"      query: {moonbit_string(scenario.query or '')},")
            lines.append(f"      expectation: {render_expectation(scenario)},")
            lines.append("    },")
        lines.append("  ]")
        lines.append("}")
        lines.append("")

    lines.append("///|")
    lines.append("fn all_feature_cases() -> Array[FeatureCase] {")
    lines.append("  let cases : Array[FeatureCase] = []")
    for number in range(len(blocks)):
        lines.append(f"  cases.append(feature_cases_{number:02d}())")
    lines.append("  cases")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def render_expectation(scenario):
    if scenario.unsupported is not None:
        return f"Unsupported({moonbit_string(scenario.unsupported)})"
    kind, payload = scenario.expectation
    if kind in ("Unordered", "Ordered"):
        return f"{kind}({moonbit_array(payload, moonbit_string)})"
    if kind == "Count":
        text = payload
        if text.endswith("L"):
            text = text[:-1]
        return f"Count({text}L)"
    if kind == "AnyOf":
        return f"AnyOf({moonbit_array(payload, moonbit_string)})"
    if kind == "GraphCount":
        count, query = payload
        if count.endswith("L"):
            count = count[:-1]
        return f"GraphCount({count}L, {moonbit_string(query)})"
    if kind in ("Empty", "Raises"):
        return kind
    if kind == "SideEffects":
        pairs = []
        for row in payload:
            if len(row) >= 2:
                pairs.append(
                    "(" + moonbit_string(row[0]) + ", " + moonbit_string(row[1]) + ")"
                )
        return "SideEffects([" + ", ".join(pairs) + "])"
    return 'Unsupported("unknown assertion")'


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
            print(f"{OUTPUT} is out of date; run scripts/gen_gremlin_cases.py")
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
