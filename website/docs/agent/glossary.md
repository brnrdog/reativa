# Glossary

The terms every other page uses, with their exact meaning in reativa.

- **Signal** (`'a Signal.t`): a mutable reactive value. `Signal.get` reads it and, inside a computed or effect, records a dependency; `Signal.peek` reads without recording.
- **Computed**: a read-only signal whose value is derived (`Computed.make`). Lazy: it recomputes on the first read after a dependency changed. Detached from its sources while nothing reads it.
- **Effect**: a function re-run whenever a signal it read changes (`Effect.run`). May return a cleanup.
- **Tracked read**: a `Signal.get` made while a computed or effect is running. **Eager read**: a `Signal.get` evaluated immediately in an expression, not inside a nested `fun`; the ppx turns eager reads in markup into tracked ones.
- **Owner**: a scope that disposes what was created under it (effects, computeds, cleanups, child owners). Components, effect runs, keyed rows, regions, boundaries, portals and mount roots have one.
- **Component**: a module with a `component` function, used as a tag (`<Card />`). Its body runs at mount time, untracked, under its own owner.
- **View** (`View.t`): a description of DOM nodes. Mounting builds the nodes once.
- **Leaf**: a reactive text node or attribute; an effect writes it in place.
- **Region**: part of a view rebuilt wholesale when its reads change (`View.dyn`, `View.show`, a `View.child` thunk). Marked in the DOM by a comment anchor.
- **Keyed list**: `View.for_with_key`; rows are kept by key across updates.
- **Template**: an HTML skeleton parsed once and cloned per instance (`View.template`); what the ppx compiles mlx element trees to.
- **Hole**: a dynamic part of a template (an attribute, event, text or child view), addressed by a child-index path.
- **Backend**: Melange or js_of_ocaml; implements the `Dom`, `History` and `Promise` virtual modules.
- **Devtools**: `Reativa.Devtools`, an opt-in record of what the graph does. **reativa-inspect**: the CLI/MCP tool over it.
