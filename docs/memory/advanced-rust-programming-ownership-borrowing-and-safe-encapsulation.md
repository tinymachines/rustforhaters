# Advanced Rust Programming: Ownership, Borrowing, and Safe Encapsulation

## Introduction

This talk explores advanced Rust programming techniques, focusing on how Rust tackles complex software engineering problems beyond just memory safety. While Rust is often associated with preventing memory-related bugs, its design philosophy extends much further into resource management, encapsulation, and building reliable software systems.

## What is Rust?

Rust has evolved in its self-description over the years:

- **2015 Definition**: "A systems programming language that runs blazingly fast, prevents nearly all segfaults, and guarantees thread safety"
- **2018 Definition**: "A language empowering everyone to build reliable and efficient software"

The shift emphasizes **reliability** - Rust addresses not just local bugs within functions, but complex interaction bugs between components that often manifest as "action at a distance" problems.

## Core Language Concepts

At its foundation, Rust is built around two main constructs:

1. **Data structures**: structs (multiple fields) and enums (alternatives)
2. **Functions**: Everything in Rust is a function call - no constructors, no automatic inheritance

This simplicity makes Rust more functional-language-like than many expect.

## Ownership: The Foundation

Every value in Rust has exactly one unique owner. This owner has full rights to:
- Mutate the data
- Destroy the data
- Pass ownership to other parts of the system

### Resource Management Beyond Memory

Ownership isn't just about memory - it's about **resource safety**. Consider these examples:

```rust
struct Point {
    x: i32,
    y: i32,
}

struct File {
    // Internal fields are hidden - encapsulation!
    // This represents a kernel resource, not just a number
}
```

The key insight: A `File` owns a system resource that must be properly managed. Rust's ownership ensures resources are cleaned up automatically when dropped.

### Drop Trait Example

```rust
impl Drop for Point {
    fn drop(&mut self) {
        println!("Dropping point");
    }
}

fn main() {
    let point = Point { x: 1, y: 2 };
    println!("Point created");
    // Point automatically dropped here
}
```

Rust's `File` type notably has **no close method** - the way to close it is to drop it, leveraging the ownership system's lifecycle management.

## Borrowing: Controlled Access

Borrowing allows values to be referenced while the owner promises not to touch the data.

### Two Types of References

1. **Immutable references (`&T`)**:
   - Can be shared (multiple references allowed)
   - Guarantee: No mutation observable through these references
   - Stronger than "you can't mutate" - "nobody can mutate"

2. **Mutable references (`&mut T`)**:
   - Unique (only one at a time)
   - Cannot alias with any other references
   - Exclusive access in both space and time

```rust
fn takes_ownership(point: Point) { /* ... */ }
fn takes_borrow(point: &Point) { /* ... */ }
fn takes_mut_borrow(point: &mut Point) { /* ... */ }
```

### Borrow Checking

Rust uses **region-based memory management** for borrow checking:

```rust
let data = Point { x: 1, y: 2 };     // data lives: line 1-4
let reference = &data;                // borrowed: line 2-4
println!("{:?}", reference);
drop(data);  // ❌ Error! Trying to drop while borrowed
```

The compiler draws regions and ensures borrowing regions fit within ownership regions.

## Software Architecture Implications

### Ownership as Decoupling

```rust
// Strong decoupling - callee takes full control
fn submit_write_op(file: File, data: String) { /* ... */ }

// Moderate coupling - caller keeps data, gives up file
fn write_to_file(file: File, data: &str) { /* ... */ }

// Strong coupling - caller retains control of both
fn write_to_file_borrowed(file: &mut File, data: &str) { /* ... */ }
```

**Key insight**: Ownership and borrowing are **contracts** that directly express software architecture decisions.

- **Ownership** = Decoupling tool (fire-and-forget)
- **Borrowing** = Coupling mechanism (caller makes promises to callee)

## Interior Mutability: The Mutex Example

How can we get mutable access from immutable references? Through **interior mutability**.

### Mutex Implementation

```rust
use std::sync::Mutex;

struct Counter {
    value: i32,
}

fn main() {
    let data = Counter { value: 0 };
    let mutex = Mutex::new(data);  // Takes ownership!
    
    manipulate_counter(&mutex);    // Immutable borrow of mutex
}

fn manipulate_counter(mutex: &Mutex<Counter>) {
    let mut guard = mutex.lock().unwrap();
    guard.value += 1;  // Mutable access from immutable reference!
}
```

### How This Works

The mutex acts as an **immutable fortress** around mutable data:

1. Immutable access to the mutex (can't destroy it)
2. Lock operation returns a guard (ownership of the lock state)  
3. Guard provides controlled mutable access to inner data
4. Guard's `Drop` implementation automatically unlocks

```rust
// Simplified mutex implementation
pub struct Mutex<T> {
    data: UnsafeCell<T>,
    // locking machinery
}

pub struct MutexGuard<'a, T> {
    mutex: &'a Mutex<T>,
}

impl<T> Mutex<T> {
    pub fn lock(&self) -> MutexGuard<T> {
        // Platform-specific locking
        MutexGuard { mutex: self }
    }
}

impl<T> MutexGuard<'_, T> {
    fn borrow_mut(&mut self) -> &mut T {
        unsafe {
            // SAFETY: We hold the lock, so we have exclusive access
            &mut *self.mutex.data.get()
        }
    }
}

impl<T> Drop for MutexGuard<'_, T> {
    fn drop(&mut self) {
        // Unlock the mutex
    }
}
```

## Unsafe Rust: Managing, Not Eliminating Risk

Rust was never about removing unsafety - it's about **managing and encapsulating** it.

### Unsafe Blocks

```rust
unsafe {
    // SAFETY: We hold the mutex lock, guaranteeing exclusive access
    &mut *ptr
}
```

**Important**: The number of lines of unsafe code is not what matters. What matters is the **scope of the safety argument** needed to justify that the unsafe code is correct.

### Encapsulation Strategy

1. **Isolate unsafe code** in small, well-defined modules
2. **Build safe interfaces** around unsafe implementations  
3. **Document safety invariants** clearly
4. **Review safety arguments** when making changes

## Key Takeaways

### Questions to Ask When Programming Rust

1. **What resources do I manage?** (Beyond just memory)
2. **What are their lifecycles?** 
3. **How can I encode invariants in data structures?**
4. **How do I encapsulate complexity?**
5. **If using unsafe, what's my safety argument?**

### Design Principles

- **Ownership thinking** governs all resource lifecycles
- **Borrowing contracts** are stronger than they appear
- **Ownership often beats borrowing** for component boundaries
- **Interior mutability and unsafe** are core language features, not escape hatches
- **Encapsulation** makes unsafe code manageable and reusable

### Concurrency Benefits

Rust's memory safety around concurrency comes **by definition**:

- `fn modify_string(s: &mut String)` is inherently concurrency-safe
- Mutable references are unique in both space **and time**
- Immutable references guarantee no observable mutation during their lifetime

## Conclusion

Advanced Rust programming is about understanding how ownership, borrowing, interior mutability, and unsafe code work together to build reliable systems. The language provides powerful tools for encapsulation and resource management that extend far beyond memory safety into general software architecture principles.

The key is learning to think in terms of resource lifecycles, ownership contracts, and safe abstractions - skills that make complex systems more reliable and maintainable.