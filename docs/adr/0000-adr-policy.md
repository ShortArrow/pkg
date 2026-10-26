# 0000. How this repository keeps its decision records

- Status: Accepted

## Context

This repository serves packages that several projects depend on, and
its design is settled one decision at a time, often while another
project waits on the answer. The reasons for each decision, and the
alternatives turned down, need one place a reader can trust to be
current.

## Decision

- Each decision record is a file `docs/adr/NNNN-<slug>.md`, numbered in
  order with four digits. A number is never reused, even for a withdrawn
  record.
- Records are written in English. The title line is `# NNNN. <Title>`,
  followed by one field, `- Status:`, and no date: git history records
  when a record was written and changed.
- The status is one of:
  - `Draft`: still being decided.
  - `Accepted`: decided.
  - `Withdrawn`: its subject was dropped, with nothing in its place.
- The sections are `Context`, `Decision`, `Alternatives`,
  `Open questions`, `Consequences` and `Verification`, in that order. A
  section with nothing to hold is left out. `Verification` holds
  the measurements the decision rests on, each with the conditions it
  was taken under, such as the image and the tool versions, and no
  date, time or commit: git history records when it was taken.
- A record moves from `Draft` to `Accepted` only when `Open questions`
  is empty.
- When a decision changes, its record is rewritten in place, whatever
  its status, so that it states the decision now in force. The design it
  replaces moves to `Alternatives`, with the reason it was dropped.
- A record holds why a decision was made and why the alternatives were
  not. How the repository works today is described in the README and in
  the code, which follow every change.

## Alternatives

- Freezing an accepted record and recording a changed decision in a new
  record that supersedes it. The decision in force would then be spread
  over a chain of records, and a reader would have to follow every
  `Superseded by` link to learn it. The text of every earlier version
  is already kept in git history.
- Dating each measurement in `Verification`, with the commit and the
  time it was taken. The section read as a log of when things were
  tried rather than the facts the decision rests on, and git history
  already records when each was written.

## Consequences

- One record per subject gives the decision in force and every design
  turned down for it.
- A rewrite of an accepted record is reviewed like any other change, in
  a pull request that names what was dropped and why.
