# Dashboard Contracts

The runtime OpenAPI contract is served by Observer Core at:

```text
http://127.0.0.1:43127/api/openapi.json
```

The TypeScript DTOs used by the web client live in:

```text
apps/observer-web/src/types.ts
```

For v0 these are intentionally small and mirror the Swift `DashboardContracts.swift`
models. Future iterations should generate the TypeScript contract from OpenAPI instead
of maintaining it manually.
