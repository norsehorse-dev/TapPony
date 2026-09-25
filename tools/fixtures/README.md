# Fixture generator

`ref.py` is a reference implementation of PROFILE_SCHEMA.md sections 3 to 10 in plain Python. `gen_fixtures.py` renders every vector through it, asserts a hand-checked expectation for each, and writes `../../fixtures/*.json`.

```
python3 gen_fixtures.py
```

Change the spec, then this generator, then both cores. Copy the regenerated `fixtures/` into the other repo in the same change.
