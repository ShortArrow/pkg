# 0000. How this repository keeps its decision records

- Status: Accepted

## Context

This repository serves packages that several projects depend on, and
its design is settled one decision at a time, often while another
project waits on the answer. The reasons for each decision, and the
alternatives turned down, need one place that does not move once the
decision is made.

## Decision

- Each decision record is a file `docs/adr/NNNN-<slug>.md`, numbered in
  order with four digits. A number is never reused, even for a withdrawn
  record.
- Records are written in English. The title line is `# NNNN. <Title>`,
  followed by one field, `- Status:`, and no date: git history records
  when a record was written and changed.
- The status is one of:
  - `Draft`: still being decided, and edited in place.
  - `Accepted`: decided. Its text is frozen.
  - `Superseded by NNNN`: replaced by a later record.
  - `Withdrawn`: abandoned without a replacement.
- The sections are `Context`, `Decision`, `Open questions`,
  `Consequences` and `Verification`, in that order. `Verification` holds
  measurements with the date and conditions they were taken under, and
  is left out when there are none.
- A record moves from `Draft` to `Accepted` only when `Open questions`
  is empty, and the section is then removed.
- An accepted record changes only in its `Status` line, and in fixes to
  typos and broken links that leave its meaning as it was. A changed
  decision is a new record that names the one it replaces, and that
  record's status becomes `Superseded by` the new number.
- A record holds why a decision was made and why the alternatives were
  not. How the repository works today is described in the README and in
  the code, which follow every change.

## Consequences

- Reading the latest record on a subject, and following `Superseded by`
  links, gives the decision in force.
- Any change to what an accepted record says, however small, costs a
  new record.
