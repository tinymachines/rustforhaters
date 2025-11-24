# Chapter 4: Vec — Dynamic Arrays

> *"Vec is a (pointer, capacity, length) triplet."*  
> — Rustonomicon

## Introduction

Box gives us a single heap allocation. But what if we need a collection that grows? Enter `Vec<T>`, Rust's dynamic array — the most commonly used collection type.

Vec builds on everything we've learned: Layout for calculating memory requirements, the Allocator traits for getting memory, and ownership semantics for safe resource management. But it adds crucial new complexity: **capacity management** and **growth strategies**.

---

## 4.1 The Vec Memory Model

### The Three-Field Structure

```rust
pub struct Vec<T, A: Allocator = Global> {
    buf: RawVec<T, A>,
    len: usize,
}

// And RawVec contains:
pub(crate) struct RawVec<T, A: Allocator = Global> {
    ptr: Unique<T>,
    cap: Cap,
    alloc: A,
}
```

Effectively, Vec has three pieces of state:
- **ptr**: Pointer to the heap allocation
- **len**: Number of elements currently stored
- **cap**: Total capacity (elements that *could* be stored)

**Invariant**: `len ≤ cap` always.

### Memory Layout

```
Stack (Vec struct):          Heap (backing buffer):
┌─────────────────┐          ┌───┬───┬───┬───┬───┬───┬───┬───┐
│ ptr ────────────┼─────────>│ A │ B │ C │ D │ ? │ ? │ ? │ ? │
├─────────────────┤          └───┴───┴───┴───┴───┴───┴───┴───┘
│ len: 4          │           ◄──── len ────►◄── unused ──►
├─────────────────┤           ◄─────────── cap ───────────►
│ cap: 8          │
└─────────────────┘
```

**On the stack**: 24 bytes (three `usize` values on 64-bit)  
**On the heap**: `cap * size_of::<T>()` bytes

### Empty Vec: No Allocation

```rust
let v: Vec<i32> = Vec::new();
// ptr: dangling (not null, but not allocated)
// len: 0
// cap: 0
```

A brand new Vec doesn't allocate until you push the first element. The pointer is "dangling" — a valid, non-null pointer that doesn't point to allocated memory.

---

## 4.2 RawVec: The Allocation Engine

Vec delegates all allocation logic to `RawVec`. This separation of concerns keeps Vec focused on element management while RawVec handles bytes.

### Why Separate RawVec?

1. **Reusability**: Other types can use RawVec (like `VecDeque`)
2. **Complexity isolation**: Allocation edge cases live in one place
3. **Unsafe encapsulation**: RawVec contains the unsafe code

### Key RawVec Operations

```rust
impl<T, A: Allocator> RawVec<T, A> {
    // Create with specific capacity
    pub fn with_capacity_in(capacity: usize, alloc: A) -> Self;
    
    // Grow to fit at least one more element
    pub fn grow_one(&mut self);
    
    // Grow with amortized strategy
    pub fn grow_amortized(&mut self, len: usize, additional: usize);
    
    // Grow to exact size
    pub fn grow_exact(&mut self, len: usize, additional: usize);
    
    // Current capacity
    pub fn capacity(&self) -> usize;
}
```

---

## 4.3 Growth Strategies: The Amortized Analysis

### The Problem with Naive Growth

If Vec grew by exactly one element each time:
```rust
let mut v = Vec::new();
for i in 0..1000 {
    v.push(i);  // Reallocates every single time!
}
```

Each push would:
1. Allocate new buffer (size n+1)
2. Copy n elements
3. Free old buffer

Total work: 1 + 2 + 3 + ... + 999 = **O(n²)** for n pushes!

### The Doubling Strategy

Instead, Vec doubles capacity when full:
```
Push 1: cap 0 → 4 (allocate)
Push 2-4: cap 4 (no realloc)
Push 5: cap 4 → 8 (realloc, copy 4)
Push 6-8: cap 8 (no realloc)
Push 9: cap 8 → 16 (realloc, copy 8)
...
```

Reallocations happen at: 1, 4, 8, 16, 32, 64, 128, 256, 512...

For 1000 elements: ~10 reallocations, copying 1+4+8+16+...+512 ≈ 1023 elements.

Total work: **O(n)** for n pushes — amortized O(1) per push!

### The Math (Optional)

For n elements with doubling:
- Number of reallocations: log₂(n)
- Total elements copied: 1 + 2 + 4 + ... + n/2 = n - 1

So n pushes cost O(n) work total, meaning O(1) amortized per push.

### Rust's Actual Growth Factor

Rust uses approximately 2x growth, but with nuances:
```rust
// From RawVec::grow_amortized
let cap = cmp::max(self.cap * 2, required);
```

---

## 4.4 Push and Pop

### Push: The Heart of Vec

```rust
pub fn push(&mut self, value: T) {
    // 1. Check if we need to grow
    if self.len == self.buf.capacity() {
        self.buf.grow_one();
    }
    
    // 2. Write the value
    unsafe {
        let end = self.as_mut_ptr().add(self.len);
        ptr::write(end, value);
    }
    
    // 3. Increment length
    self.len += 1;
}
```

Step by step:
1. **Capacity check**: If `len == cap`, we're full — grow the buffer
2. **Calculate position**: `ptr + len` is the first unused slot
3. **Write value**: `ptr::write` because the slot is uninitialized
4. **Update length**: Now we have one more element

### Pop: Simple and Efficient

```rust
pub fn pop(&mut self) -> Option<T> {
    if self.len == 0 {
        None
    } else {
        self.len -= 1;
        unsafe {
            Some(ptr::read(self.as_ptr().add(self.len)))
        }
    }
}
```

Note: **Pop never shrinks the buffer!** Capacity stays the same. This is intentional:
- Shrinking would require reallocation
- You might push again soon
- Use `shrink_to_fit()` if you really want to reclaim memory

---

## 4.5 Reallocation: The Three Possibilities

When Vec needs more space, the allocator has options:

### 1. In-Place Extension (Rare but Optimal)

If there's free memory right after the current allocation:
```
Before: [A B C D][free space     ]
After:  [A B C D _ _ _ _         ]
```
No copying needed! Just extend the allocation.

### 2. Allocate-Copy-Deallocate (Common)

```
Before: [A B C D][other allocation]
              ↓
        Allocate new buffer elsewhere
              ↓
After:  [_ _ _ _ _ _ _ _]
        Copy: A B C D
        [A B C D _ _ _ _]
              ↓
        Free old buffer
```

### 3. Failure

If the allocator can't satisfy the request:
- `push` and similar methods panic (via `handle_alloc_error`)
- `try_reserve` returns `Err(TryReserveError)`

---

## 4.6 Drop: Cleaning Up Collections

```rust
unsafe impl<#[may_dangle] T, A: Allocator> Drop for Vec<T, A> {
    fn drop(&mut self) {
        unsafe {
            // Drop all elements
            ptr::drop_in_place(ptr::slice_from_raw_parts_mut(
                self.as_mut_ptr(), 
                self.len
            ))
        }
        // RawVec::drop handles deallocation
    }
}
```

Two phases:
1. **Drop each element**: Calls destructor on `v[0]`, `v[1]`, ..., `v[len-1]`
2. **Deallocate buffer**: RawVec's Drop frees the memory

### What About Panics?

If an element's destructor panics:
- Remaining elements might not be dropped (memory leak)
- But memory safety is preserved
- This is a known limitation, not a bug

---

## 4.7 Zero-Sized Types in Vec

Vec handles ZSTs specially:

```rust
let mut v: Vec<()> = Vec::new();
for _ in 0..1_000_000 {
    v.push(());  // No allocation ever happens!
}
println!("len: {}, cap: {}", v.len(), v.capacity());
// len: 1000000, cap: 18446744073709551615 (usize::MAX)
```

For ZSTs:
- `ptr` is dangling (never allocated)
- `cap` is `usize::MAX` (effectively infinite)
- `len` tracks count normally
- No memory is used except the Vec struct itself (24 bytes)

---

## 4.8 Common Vec Operations

### Reserve: Ensure Capacity

```rust
let mut v = Vec::new();
v.reserve(100);  // Guarantee space for 100 more elements
// v.capacity() >= 100
```

### Shrink: Reclaim Memory

```rust
let mut v = vec![1, 2, 3, 4, 5];
v.pop();
v.pop();
v.shrink_to_fit();  // Reduce capacity to match length
// v.capacity() == 3
```

### With Capacity: Avoid Reallocations

```rust
// If you know the size upfront
let mut v = Vec::with_capacity(1000);
for i in 0..1000 {
    v.push(i);  // No reallocations!
}
```

### Clear: Remove All Elements

```rust
let mut v = vec![1, 2, 3];
v.clear();
// len: 0, but capacity unchanged
```

---

## 4.9 Vec vs Array vs Slice

| Type | Size Known | Location | Growable |
|------|------------|----------|----------|
| `[T; N]` | Compile time | Stack* | No |
| `Vec<T>` | Runtime | Heap | Yes |
| `&[T]` | Runtime | Borrowed | No |

*Arrays can be on the heap if boxed: `Box<[T; N]>`

```rust
let array: [i32; 3] = [1, 2, 3];        // Fixed size, stack
let vec: Vec<i32> = vec![1, 2, 3];       // Dynamic, heap
let slice: &[i32] = &vec[..];            // View into vec
```

---

## 4.10 Key Takeaways

1. **Vec is a (ptr, len, cap) triplet** — 24 bytes on stack
2. **Empty Vec doesn't allocate** — Allocation happens on first push
3. **Doubling growth gives O(1) amortized push** — Essential for performance
4. **Pop doesn't shrink** — Use `shrink_to_fit` explicitly
5. **ZSTs are special-cased** — Infinite capacity, no allocation
6. **Drop is two-phase** — Elements first, then memory

---

## Source Files

| File | Purpose |
|------|---------|
| `library/alloc/src/vec/mod.rs` | Main Vec implementation |
| `library/alloc/src/raw_vec.rs` | RawVec allocation logic |
| `library/alloc/src/vec/into_iter.rs` | IntoIterator implementation |
| `library/alloc/src/vec/drain.rs` | Drain iterator |

---

## Exercises

1. Why doesn't Vec store capacity in the heap allocation header (like malloc does)?

2. Implement a `SimpleVec<T>` with just `new`, `push`, `pop`, and `Drop`.

3. What's the maximum number of reallocations for a Vec that grows to 1 million elements?

4. Why is `Vec<()>` capacity `usize::MAX` instead of some large finite number?

5. What happens if you `mem::forget` a Vec? Is this a memory leak? What about the elements?

---

## Hands-On Project: SimpleVec

Build a minimal Vec to solidify understanding:

```rust
use std::alloc::{alloc, dealloc, realloc, Layout};
use std::ptr::{self, NonNull};

pub struct SimpleVec<T> {
    ptr: NonNull<T>,
    len: usize,
    cap: usize,
}

impl<T> SimpleVec<T> {
    pub fn new() -> Self {
        SimpleVec {
            ptr: NonNull::dangling(),
            len: 0,
            cap: 0,
        }
    }

    pub fn push(&mut self, value: T) {
        if self.len == self.cap {
            self.grow();
        }
        unsafe {
            ptr::write(self.ptr.as_ptr().add(self.len), value);
        }
        self.len += 1;
    }

    pub fn pop(&mut self) -> Option<T> {
        if self.len == 0 {
            None
        } else {
            self.len -= 1;
            unsafe { Some(ptr::read(self.ptr.as_ptr().add(self.len))) }
        }
    }

    fn grow(&mut self) {
        let new_cap = if self.cap == 0 { 4 } else { self.cap * 2 };
        let new_layout = Layout::array::<T>(new_cap).unwrap();
        
        let new_ptr = if self.cap == 0 {
            unsafe { alloc(new_layout) }
        } else {
            let old_layout = Layout::array::<T>(self.cap).unwrap();
            unsafe { realloc(self.ptr.as_ptr() as *mut u8, old_layout, new_layout.size()) }
        };
        
        self.ptr = NonNull::new(new_ptr as *mut T).expect("allocation failed");
        self.cap = new_cap;
    }
}

impl<T> Drop for SimpleVec<T> {
    fn drop(&mut self) {
        if self.cap > 0 {
            // Drop all elements
            for i in 0..self.len {
                unsafe { ptr::drop_in_place(self.ptr.as_ptr().add(i)); }
            }
            // Deallocate
            let layout = Layout::array::<T>(self.cap).unwrap();
            unsafe { dealloc(self.ptr.as_ptr() as *mut u8, layout); }
        }
    }
}
```

---

## What's Next?

With Vec mastered, you understand Rust's core collection machinery. Suggested further reading:

- **String**: Essentially `Vec<u8>` with UTF-8 guarantees
- **HashMap**: Uses RawTable, a more complex allocation strategy  
- **VecDeque**: Ring buffer built on RawVec
- **BTreeMap**: Node-based allocation

You now have the foundation to understand any Rust collection at the allocation level!
