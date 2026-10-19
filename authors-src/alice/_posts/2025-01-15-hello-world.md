---
layout: post
title: Hello World
author: Alice
categories: [_posts]
tags: [welcome, jekyll]
date: 2025-01-15
---

Welcome to the template. This post lives in
`authors-src/alice/_posts/2025-01-15-hello-world.md` and is mirrored to
`_posts/alice/2025-01-15-hello-world.md` before the build, so Jekyll publishes
it as a regular post.

{% include_author note.html title="Tip" body="include_author looks in the current author's _includes folder first, then in the shared _includes folder." %}
