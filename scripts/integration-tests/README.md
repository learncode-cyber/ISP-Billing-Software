# Integration Test Harnesses

Six scripts, one per external system. Each is **production-grade**, not a
mock: it makes a real network call to the real protocol/API when
credentials or a device are supplied. When they are not, the script exits
with a machine-readable `EXTERNAL-CREDENTIAL-BLOCKED` status — it never
fabricates a PASS.

Run all six:
```bash
bash scripts/integration-tests/run-all.sh
```

Each script exits `0` for PASS, `1` for FAIL (a real defect), `2` for
`EXTERNAL-CREDENTIAL-BLOCKED` (correctly unverifiable in this environment).
A CI pipeline can therefore fail the build only on real defects (exit 1)
while surfacing blocked integrations (exit 2) as visible, not silent.
