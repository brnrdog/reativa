# Lists

## Summary

`View.for_` re-renders a whole list on change. `View.for_with_key` (and `<View.ForEach key=...>`) keeps rows by key and moves only what an update displaces.

## Availability

All releases; the reconciler was rewritten in 2.0.

## Rules

1. Keys must be unique strings; a duplicate raises `Failure`.
2. `for_with_key`: a surviving row keeps its DOM and effects; its `'a Signal.t` receives the new item. `ForEach ~key` with raw items rebuilds a row whose item changed physically.
3. Rows that keep their relative order do not move (longest increasing subsequence); swapping two rows of a thousand moves two.
4. New rows are created in order and inserted with one DOM call per run of consecutive new rows.
5. Clearing a list that is the only content of its parent empties the parent with one write.
6. Row render functions run untracked under the row's own owner.

## Patterns

```ocaml
<ul>
  (View.for_with_key (fun () -> Signal.get todos) ~key:(fun t -> string_of_int t.id) (fun todo ->
     <li className=(if (Signal.get todo).done_ then "done" else "")>((Signal.get todo).title)</li>))
</ul>
```

## Anti-patterns

- Index keys (`string_of_int i`) for lists that reorder: rows keep the wrong DOM.
- `View.for_` for long lists that change often: every change rebuilds every row.

## Edge cases

- A row's render function reading other signals does not subscribe the list (rows are untracked); read inside the row's markup.

## Verify

The benchmark (`benchmarks/`) and the DOM-op counts in `test/dom/test_keyed.ml` pin the move counts.

## Related

views.md, ownership.md
