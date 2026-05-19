# Quality Guidelines

> Code quality standards for backend development.

---

## Overview

<!--
Document your project's quality standards here.

Questions to answer:
- What patterns are forbidden?
- What linting rules do you enforce?
- What are your testing requirements?
- What code review standards apply?
-->

(To be filled by the team)

---

## Convention: User-Facing Git Notes Prefer Chinese

**What**: When this project is used in Chinese collaboration, user-facing git explanations should default to Chinese.

**Why**:
- The user reads commit/upload explanations faster in Chinese.
- The git commit message itself may stay English or mixed, but the assistant's explanation around it should be Chinese-first.
- This reduces handoff friction during frequent Trellis `commit` / `finish-work` flows.

**Required Pattern**:
- Before running `git commit`, explain the commit plan to the user in Chinese.
- After committing, report the commit hash and what it contains in Chinese.
- If a tool emits English logs, summarize the important result in Chinese instead of forwarding the raw log only.

**Example**:
```text
这次提交会包含三部分：
1. 第三层权重顺序修正
2. 整网 CNN_tb 与 PC 对拍
3. Trellis 规范补充
```

---

## Forbidden Patterns

<!-- Patterns that should never be used and why -->

(To be filled by the team)

---

## Required Patterns

<!-- Patterns that must always be used -->

(To be filled by the team)

---

## Testing Requirements

<!-- What level of testing is expected -->

(To be filled by the team)

---

## Code Review Checklist

<!-- What reviewers should check -->

(To be filled by the team)
