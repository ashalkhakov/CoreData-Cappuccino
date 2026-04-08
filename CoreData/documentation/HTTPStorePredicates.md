# CPHTTPStore – OrdersAPI client store

`CPHTTPStore` is a `CPPersistentStore` subclass that targets the OrdersAPI
`cdFetch` / `cdSave` endpoints.  It is the recommended backend for Cappuccino
applications that use the OrdersAPI as their server.

---

## Setup

```objj
var coordinator = [[CPPersistentStoreCoordinator alloc]
                        initWithManagedObjectModel:myModel
                                         storeType:[CPHTTPStoreType class]
                                storeConfiguration:[CPDictionary dictionaryWithObjectsAndKeys:
                                    // Full path to the OrdersAPI root (no trailing slash)
                                    @"http://myserver/WebObjects/App.woa/0/wa/OrdersAPI",
                                                         CPHTTPStoreBaseURL,
                                    1,               CPHTTPStoreDefaultIncludeDepth,
                                    nil]];
var context = [[CPManagedObjectContext alloc]
                    initWithPersistentStoreCoordinator:coordinator];
```

### Configuration keys

| Key                            | Type     | Description                                                |
|-------------------------------|----------|------------------------------------------------------------|
| `CPHTTPStoreBaseURL`           | String   | **Required.** OrdersAPI root URL (no trailing slash).      |
| `CPHTTPStoreTimeout`           | Number   | Optional request timeout in seconds.                       |
| `CPHTTPStoreDefaultIncludeDepth` | Number | Default relationship include depth (default: 1).           |

---

## Fetch predicates

Predicates are encoded from `CPFetchRequest.predicate`.  The value may be:

1. A **`CPComparisonPredicate`** or **`CPCompoundPredicate`** object.
2. A **raw `CPDictionary`** that directly represents the AST (pass-through).

### Supported operators

| Cappuccino operator       | Server AST `op`  | Example AST                                            |
|--------------------------|-----------------|--------------------------------------------------------|
| `==`                     | `"=="`           | `{"op":"==","key":"status","value":"paid"}`            |
| `!=`                     | `"!="`           | `{"op":"!=","key":"status","value":"cancelled"}`       |
| `<`                      | `"<"`            | `{"op":"<","key":"amount","value":100}`                |
| `<=`                     | `"<="`           | `{"op":"<=","key":"amount","value":100}`               |
| `>`                      | `">"`            | `{"op":">","key":"amount","value":0}`                  |
| `>=`                     | `">="`           | `{"op":">=","key":"amount","value":0}`                 |
| `contains`               | `"contains"`     | `{"op":"contains","key":"name","value":"Smith"}`       |
| `beginswith`             | `"beginswith"`   | `{"op":"beginswith","key":"fullName","value":"I"}`     |
| `in`                     | `"in"`           | `{"op":"in","key":"status","value":["new","pending"]}` |
| `== nil`                 | `"isnull"`       | `{"op":"isnull","key":"deletedAt"}`                    |
| `!= nil`                 | `"notnull"`      | `{"op":"notnull","key":"deletedAt"}`                   |

### Compound predicates

| Type    | AST                                              |
|---------|--------------------------------------------------|
| `and`   | `{"op":"and","subs":[...]}`                      |
| `or`    | `{"op":"or","subs":[...]}`                       |
| `not`   | `{"op":"not","sub":{...}}`                       |

---

## Fetch examples (matching debug.log)

### Simple beginswith fetch

```objj
var req = [[CPFetchRequest alloc] init];
[req setEntity:[model entityWithName:@"Customer"]];
[req setPredicate:@{
    @"op":    @"beginswith",
    @"key":   @"fullName",
    @"value": @"I"
}];
var sd = [[CPSortDescriptor alloc] initWithKey:@"fullName" ascending:YES];
[req setSortDescriptors:[sd]];
[req setFetchLimit:10];
[req setFetchOffset:0];

var results = [context executeStoreFetchRequest:req];
```

Produces the cdFetch request:

```json
{
  "entity": "Customer",
  "predicate": { "op": "beginswith", "key": "fullName", "value": "I" },
  "sort": [{ "key": "fullName", "dir": "asc" }],
  "limit": 10,
  "offset": 0
}
```

### IDs-only / fault mode

Set `transparentFetch = YES` on the fetch request to receive lightweight
"fault" objects that are hydrated on first property access:

```objj
[req setTransparentFetch:YES];
```

Adds `"return": {"onlyIDs": true}` to the cdFetch body.

### Relationship inclusion

Pass relationship key paths in `relationshipKeyPathsForPrefetching` to include related objects alongside the primary fetch:

```objj
[req setRelationshipKeyPathsForPrefetching:[@"shippingAddress", @"orders"]];
```

Adds `"include": {"relationships": ["shippingAddress","orders"], "depth": 1}`.

### Count result type

Set `resultType` to `CPCountResultType` to request a server-side count instead of objects:

```objj
[req setResultType:CPCountResultType];
```

Adds `"resultType": "count"` to the cdFetch body.

### Compound predicate (and)

```objj
var pred = @{
    @"op": @"and",
    @"subs": @[
        @{ @"op": @"==",          @"key": @"status",  @"value": @"new" },
        @{ @"op": @"beginswith",  @"key": @"fullName", @"value": @"A"  }
    ]
};
[req setPredicate:pred];
```

### In operator

```objj
var pred = @{
    @"op":    @"in",
    @"key":   @"status",
    @"value": @[@"new", @"pending", @"paid"]
};
[req setPredicate:pred];
```

---

## Save

Call `[context saveChanges:nil]` as usual.  The store will call `cdSave` with
three arrays:

* **inserted** – new objects (with `{ "temp": "t_<localID>" }` IDs)
* **updated**  – modified objects (includes `expectedVersion` for optimistic
  locking if the object has a `version` attribute)
* **deleted**  – deleted objects (by server ID)

After a successful save:

* Temporary IDs are replaced by real server IDs (from `idMap`).
* Object version numbers are updated from `versions` in the response.
* Returned objects (when `return.inserted == true`) are materialised and
  merged into the context.

---

## Object identity

Server IDs `{ entity, pk }` are mapped to a stable `globalID` string:

```
"Entity|key=val;"             (single-column PK)
"Entity|k1=v1;k2=v2;"        (composite PK, keys sorted alphabetically)
```

Examples:

```
{ entity:"Customer", pk:{ customerID:1075 } }  →  "Customer|customerID=1075;"
{ entity:"Order",    pk:{ orderID:245 }     }  →  "Order|orderID=245;"
```

This is the same key format that the OrdersAPI uses for `objectsByID` dict
keys.

---

## Fault firing

When a fault object (returned from IDs-only mode) has one of its relationship
or attribute properties accessed, `CPManagedObject.storedValueForKey:` calls
`CPManagedObjectContext.updateObjectWithID:mergeChanges:`, which now delegates
to `CPManagedObjectContext._fetchObjectWithID:`.  That method calls
`CPHTTPStore.fetchObjectsWithID:fetchProperties:error:`, which issues a
`cdFetch` with the `ids` array to hydrate the object from the server.
