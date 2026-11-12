# Migrating to 2.0

## Summary

2.0 adds ownership, lifecycle, refs, context, error boundaries, portals, resources with suspense, templates and devtools. Three changes can break existing code.

## Rules

1. **Components are lazy.** A component used as a tag (`<Card />`) runs when the view is mounted, untracked, under its own owner — not when the view value is built. Effects, computeds and cleanups it creates are disposed when the region holding it re-renders or is removed.
   - Code that relied on the body running at construction (e.g. registering something globally while building the tree) must move that work out of the component or into `View.on_mount`.
   - A `Signal.get` in a component body no longer subscribes the surrounding region. Read inline in the markup (`<p>(Signal.get x)</p>`), or wrap the part that must rebuild in `View.tracked`.
   - Calling `Module.component ~props` directly is unchanged (eager).
2. **The public API is what the `.mli` files declare.** `View.t` and `View.attr` are abstract (build them with `View.*`), a signal's record fields are hidden (use `Signal.peek`/`Signal.set`), and router/renderer internals are gone.
3. **Templates.** mlx element trees compile to templates. Behaviour is the same; generated code no longer uses `View.Mlx`, so the ppx silences the unused-open warning on `open Reativa.View.Mlx`. Pass `-no-templates` to the ppx to compare.

## Verify

Build with the new release; fix type errors from rule 2. Then check components whose bodies read signals (rule 1): in the browser, or with reativa-lens (`--act` the interaction that should update them).

## Related

ownership.md, mlx.md
