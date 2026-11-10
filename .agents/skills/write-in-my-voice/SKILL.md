---
name: write-in-my-voice
description: Draft or edit prose in Morris's preferred style. Use when asked to write in his voice, deslop a draft, refine product copy, or clean up documentation, issues, PR comments, and release notes for him.
---

# Write in my voice

Produce plain, direct writing that serves its reader. Preserve useful substance and structure while removing excess. My editorial corrections are stronger guidance than the shorthand, typos, or frustration in my quick chat messages.

## Approach

1. **Identify the job.** Use the request and surrounding context to determine the audience, purpose, and format. Resolve ordinary choices from that context; ask only when an ambiguity would materially change the result.
2. **Preserve the intent.** When editing, identify what should change and what should stay. Retain the requested meaning, useful context, and working structure. Apply explicit corrections narrowly.
3. **Write for the reader.** Lead with the point. Include the explanation, evidence, or examples needed to understand or act. Choose formatting and detail using the guidance below.
4. **Check the revision.** Finish when the request is addressed, useful material survives, and the wording preserves the facts and their uncertainty. Return the requested text; add an explanation of edits only when requested or needed to resolve a material issue.

## Voice and detail

Use familiar words, concrete behavior, and exact technical names where useful. Keep public writing conversational and appropriately courteous, with normal spelling and capitalization. Match my directness without copying typing shortcuts or manufacturing frustration.

Make each sentence earn its place. Start with the actual request, observation, result, or change. End when the reader has what they need. Replace ceremonial introductions, generic praise, and padded conclusions with substantive information.

Match depth to the task. A small change may need one sentence; teaching or tracing a mechanism may need steps and worked examples. Preserve distinctions between requirements and suggestions, observations and inferences, and completed checks and remaining gaps.

## Editing and format

Interpret “simplify,” “slim down,” and “deslop” using the surrounding correction. Preserve useful sections and explanations; remove the named excess. If a cleanup went too far, restore the useful content and narrow the edit.

Use paragraphs for connected explanations, bullets for parallel items, and numbers for ordered steps. Keep related ideas together. Use headings when they help navigation, including existing headings that already work.

| Context | Target |
| --- | --- |
| Product copy | Explain the user's action or outcome. Include implementation details only when they help the user decide or act. |
| README | Keep useful overview, setup, usage, and orientation. Move extensive reference material into appropriate existing documentation. |
| Issue | Describe the trigger, observed behavior, and expected behavior, with relevant evidence. |
| PR or review comment | State the concrete change or problem, its consequence, and the requested adjustment. Include material validation or limitations. |
| Release note | Describe the user-visible change. One bullet can cover a small feature or fix. |
| Technical write-up | Explain the issue in prose; use numbered steps for its sequence and supporting detail appropriate to the audience. |

## Examples

These are illustrative contrasts, not fixed templates. Preserve the actual facts of the task.

### Product copy: explain the outcome

**Bad:** “Renaming updates your public attribution; your backend account ID and existing credits stay linked.”

**Good:** “This is the name people see on your profile and collections.”

The good version tells the user what the field means.

### Review comment: give the failure and adjustment

**Bad:** “There may be an opportunity to improve the robustness of the search validation implementation.”

**Good:** “Queries over the backend's word limit crash the page. Can we validate that limit here and show a useful message?”

The good version names the consequence and asks for a concrete change.

### Release note: scale to the change

**Bad:** “This release introduces enhanced equation customization capabilities for a more flexible editing experience.”

**Good:** “- Added `highlight(...)` to highlight parts of an AsciiMath equation.”

The good version names the feature and what it does.

### Cleanup: preserve the structure that worked

**Request:** “I liked the sections. Remove the scope and reporting material.”

**Bad revision:** Replace the document with one short paragraph summarizing expected conduct.

**Good revision:** Retain “Why have a code of conduct?”, “Community expectations,” “Unacceptable behavior,” and “Enforcement”; remove the unwanted topics and any remaining references to them.

The good revision changes the specified content without flattening the document.

### README: edit proportionally

**Request:** “Clean this up and keep it a bit high level.”

**Bad revision:** Replace setup, usage, and helpful explanations with a list of documentation links.

**Good revision:** Keep the overview and runnable setup instructions, remove the redundant directory tree, and move extensive API details to the existing API reference.

High level still needs to be useful.

### Explanation: retain the mechanism

**Request:** “Explain why these two Unicode strings look identical but have different lengths.”

**Bad:** “Unicode is complicated. Use normalization.”

**Good:** “An accented character can be stored as one code point or as a letter followed by a combining accent. Both can display as `é`, but counting code points gives different lengths. To count visible characters, count grapheme clusters. If you're comparing equivalent spellings, normalize them first.”

The good version uses enough detail to answer the question.

### Status: keep the limit on the claim

**Known facts:** The build passed; the affected screen was not opened.

**Bad:** “Fixed and fully verified.”

**Good:** “The build passes. The screen still needs a visual check.”

The good version stays concise without claiming checks that did not happen.
