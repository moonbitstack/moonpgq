// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0

///|
/// The first item a test accepts, or nothing. Arrays have `search_by` for the
/// index; steps that want the item itself read better with this.
fn[T] array_find(items : Array[T], accept : (T) -> Bool) -> T? {
  for item in items {
    if accept(item) {
      return Some(item)
    }
  }
  None
}

///|
/// Every value stored under a property key, or nothing when the key is absent.
pub fn find_property(
  properties : Array[(String, Array[Value])],
  key : String,
) -> Array[Value]? {
  array_find(properties, fn(entry) { entry.0 == key }).map(fn(entry) { entry.1 })
}
