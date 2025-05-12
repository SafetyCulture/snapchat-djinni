# Kotlin Multiplatform Bindings for Djinni Interfaces 

## Overview

This repository is an **ongoing experimental effort** to generate Kotlin Multiplatform (KMP) bindings for Djinni
interfaces on iOS and Android.

Our goal is to extend Djinni's functionality to seamlessly integrate with Kotlin Multiplatform, enabling developers to
access existing shared business logic written in c++ within a Kotlin Multiplatform library targeting Android and iOS 
with minimal platform-specific implementation.

## Project Objectives

- **Automated Code Generation**: Extend Djinni to produce Kotlin bindings to allow utilisation of existing business
  logic within KMP.
- **Seamless Interoperability**: Ensure that the generated bindings are performant and interoperable with both native
  and shared Kotlin codebases.
- **Developer-Focused**: Simplify the complexity of integrating Djinni with KMP, reducing development overhead of
  transitioning shared business logic written in c++ to Kotlin Multiplatform.

## Status

This project is experimental and **under active development**. The current focus is on:

1. Investigating best practices for translating Djinni-generated interfaces into Kotlin Multiplatform code.
2. Prototyping initial bindings.
3. Testing the feasibility of smooth integration between Djinni and KMP.

As this effort is exploratory, there may be significant changes as it evolves.

## Supported Features
 Legend:
 ✅ Supported 
 ⚠️ Experimental / In Progress
 ❌ Not Supported 

### Constants
Constants are not currently supported.

### Enums

| Feature              | Support |
|----------------------|---------|
| Common generation    | ✅       |
| Special flags        | ❌       |

### Records
| Feature           | Support |
|-------------------|:-------:|
| Common generation |    ✅    |
| Extensions        |    ❌    |

| Feature | Primitives | Optional | Date | List | Set | Map | Enum | Record | External |
|---------|:----------:|:--------:|:----:|:----:|:---:|:---:|:----:|:------:|:--------:|
| Fields  |     ✅      |    ✅     |  ✅   |  ✅   |  ✅  |  ✅  |  ✅   |   ✅    |    ✅     |

### Interfaces
| Feature           | Support |
|-------------------|:-------:|
| Common generation |    ✅    |
| Static methods    |    ❌    |


| Feature    | Primitives | Optional | Date | List | Set | Map | Enum | Record | External |
|------------|:----------:|:--------:|:----:|:----:|:---:|:---:|:----:|:------:|:--------:|
| Parameters |     ✅      |    ✅     |  ✅   |  ✅   |  ✅  |  ✅  |  ✅   |   ✅    |    ✅     |

### Mapping
| Feature   | Primitives | Optional | Date | List | Set | Map<sup>1</sup> | Enum | Record<sup>2</sup> | Interfaces | External<sup>3</sup> |
|-----------|:----------:|:--------:|:----:|:----:|:---:|:---------------:|:----:|:------------------:|:----------:|:--------------------:|
| To Java   |     ✅      |    ✅     |  ✅   |  ✅   |  ❌  |       ⚠️        |  ✅   |         ⚠️         |     ❌      |          ⚠️          |
| From Java |     ✅      |    ✅     |  ✅   |  ✅   | ❌️  |       ⚠️        |  ✅   |         ⚠️         |     ❌      |          ⚠️          |
| To ObjC   |     ⚠️     |    ✅️    |  ✅   |  ❌   |  ❌  |        ❌        |  ✅   |         ⚠️         |     ❌      |          ❌           |
| From ObjC |     ⚠️     |    ✅️    |  ✅   |  ❌   |  ❌  |        ❌        |  ✅   |         ⚠️         |     ❌      |          ❌           |

<sup>1</sup>Support is limited to conversion of maps with primitive/string keys

<sup>2</sup>Records are supported so long as their field types are also supported

<sup>3</sup>External types support is limited to wire generated protobuf messages
