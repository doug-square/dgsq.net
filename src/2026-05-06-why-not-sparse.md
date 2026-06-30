---
title: Why not sparse?
date: 2026-05-06 00:00:00 -0500
tags:
slug: why-not-sparse
description:
image:
image_caption:
---

I was talking with a colleague the other day about the current industry trend to
focus so much on further quantizing today's LLM models. I'm sure the reasons for
pursuing quantization are apparent to most people who work in this industry:
going from BF16 to FP8 or NVFP4 nets what amounts to a nearly 2x or 4x reduction
in memory requirements and often a similar speedup.

But I can't shake the feeling that by focusing so much on finding the lowest
precision models, we are perhaps neglecting an equally-fundamental limitation of
our current models: that they are too dense.

I have been struggling to articulate exactly what I mean by this for a while
now, until my colleague pointed me to [The Lottery Ticket
Hypothesis](https://arxiv.org/pdf/1803.03635), by Frankle and Carbin, a paper
that is probably well known to folks who are more integrated into the machine
learning community than I. In brief, the main thesis of the paper is:

> A randomly-initialized, dense neural network contains a subnetwork that is
> initialized such that—when trained in isolation—it can match the test accuracy
> of the original network after training for at most the same number of
> iterations.

The authors then show how by iteratively training a network, pruning away the
lowest-weighted connections, and then retraining the resultant network from
scratch, they can achieve similar performance on a few benchmarks with networks
down to 1% of the size they began with. Compare this 99% savings to the gains
that we can get from quantization: many models have already been quantized to 8
bits, so even assuming we *can* get them down to 1 bit, we would be saving only
87.% on what we have today. Worth doing? Sure. But the going is getting harder,
and I don't think that we'll be getting all the way to 1 bit on every part of
every model.

Back to Frankle and Carbin: they also show that randomly selecting sub-networks
(instead of selecting based on results of training larger versions) does *not*
work as well, producing worse accuracy and slower convergence. In their words:

> The initialization that gives rise to a winning ticket is arranged in a
> particular sparse architecture. Since we uncover winning tickets through heavy
> use of training data, we hypothesize that the structure of our winning tickets
> encodes an inductive bias customized to the learning task at hand.

I find this very reminiscent of evolutionary methods like
[NEAT](https://nn.cs.utexas.edu/downloads/papers/stanley.ec02.pdf), which
likewise attempted to build bespoke sparse networks, one neuron at a time. The
difference of course, being that the Frankle and Carbin work backwards from a
very dense network and NEAT builds up a network from scratch.

I see this as different from efforts to find sparse attention mechanisms, as
sparse attention does not tend to affect the size of the model, but only how
expensive it is to operate with it.

I hope that once we're done building larger models, we can get to work on
building sparser models that more efficiently reflect the tasks they need to
perform than a series of dense operations could. After all, our brains are not
homogeneous meshes, but some sort of more contrived pattern of connections. I
have this feeling that the optimal model for most problems exists in this
sparse-yet-deep subspace, if only we could find it.

---

In other news: I'm continuing the pattern of keeping long pauses between posts,
and changing the website's theme every other post. Bad habits.
