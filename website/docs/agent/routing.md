# Routing

## Summary

Client-side routing over the History API: a location signal, navigation functions, link interception and route matching.

## Rules

1. `Router.location ()` is a signal of the current location; reading it in a tracked scope subscribes to navigation.
2. `<Link href>` navigates in-app on a plain left click; modified clicks, other targets and external links are left to the browser.
3. `<Router>` renders the first `<Route path>` matching the location; patterns support static segments, `:params` and a trailing `*`.
4. Route params are decoded with the backend's `decodeURIComponent`.

## API

```ocaml
Router.location : unit -> Router.location Signal.t
Router.navigate : ?replace:bool -> ?state:Router.state -> string -> unit -> unit
Router.push / replace / back / forward / go
Router.route : string -> (Router.route_match -> View.t) -> Router.route
Router.outlet : ?fallback:(Router.location -> View.t) -> Router.route list -> View.t
Router.param : Router.route_match -> string -> string option
Router.link / redirect / is_active
<Router> <Route path render> <Link href> <Redirect to_>
```

## Patterns

```ocaml
<Router>
  <Route path="/"><Home /></Route>
  <Route path="/users/:id" render=(fun m -> <User id=(Option.value ~default:"" (Router.param m "id")) />) />
</Router>
```

## Related

views.md
