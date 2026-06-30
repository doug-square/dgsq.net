---
title: Gen AI and Architecture
date: 2026-06-30 00:00:00 -0500
tags:
slug: gen-ai-arch
description:
image:
image_caption:
---

Almost a decade ago, I was an intern at certain large tech company, working on a
team that no longer exists. I was living on the third floor of a house that
lodged around 15 other people who temporarily found themselves in Seattle for
one reason or another. The standard introduction included our tech stack, and so
it went when one other transient arrived one day: "I work on robotics firmware",
"I work on Chrome", "I work on drone FPGAs", "I work on devtools". And then the
new resident-for-a-month says: "Oh, well I'm more of an Ideas Guy."

Mr. Chrome laughs. The Devtooler smiles. Ideas Guy looks confused about what's
so funny.

---

Today I launched a fleet of AI agents to generate code for a fused GPU kernel,
based on some standalone kernels that a human wrote years ago. Tomorrow I'll
check back to see what it accomplished.

I will look at the code, which will have too many comments. I will compare its
performance to other alternatives. I will not understand why it made the
decisions it made.

---

In undergrad, we all went home when COVID struck. I had been looking forward to
a second summer in Seattle. I instead went back to my parent's house and
scattered electronics around my childhood bedroom. I felt isolated from my team.

The next summer, I found employment at another large Seattle-based tech
company. Then they told me I'd be working remote. I don't think I even talked
with 85% of my team before I left.

In undergrad, I looked forward to the start of the Fall semester because I knew
that meant I would be able to actually talk to people about the things I was
working on.

---

Today I spent more time "talking" to agents about kernels than speaking to my
team. They're all remote anyways.

But I don't really see much of an end in sight this time.

---

In 1956, Isaac Asimov wrote, in *The Last Question*:

> For decades, Multivac had helped design the ships and plot the trajectories
> that enabled man to reach the Moon, Mars, and Venus, but past that, Earth's
> poor resources could not support the ships. Too much energy was needed for the
> long trips. Earth exploited its coal and uranium with increasing efficiency,
> but there was only so much of both.
> 
> But slowly Multivac learned enough to answer deeper questions more
> fundamentally, and on May 14, 2061, what had been theory, became fact.
> 
> The energy of the sun was stored, converted, and utilized directly on a
> planet-wide scale. All Earth turned off its burning coal, its fissioning
> uranium, and flipped the switch that connected all of it to a small station,
> one mile in diameter, circling the Earth at half the distance of the Moon. All
> Earth ran by invisible beams of sunpower.
> 
> Seven days had not sufficed to dim the glory of it and Adell and Lupov finally
> managed to escape from the public function, and to meet in quiet where no one
> would think of looking for them, in the deserted underground chambers, where
> portions of the mighty buried body of Multivac showed. Unattended, idling,
> sorting data with contented lazy clickings, Multivac, too, had earned its
> vacation and the boys appreciated that. They had no intention, originally, of
> disturbing it.
>
> They had brought a bottle with them, and their only concern at the moment was
> to relax in the company of each other and the bottle.

But I am hundreds of miles from my nearest teammate. And I don't drink.

---

Today at ISCA, there was a panel on the topic of AI in Computer Architecture
Research. The panel seemed to be of the opinion that AI was a good tool to be
used in our research, but was not going to replace us, as architecture
researchers would still be needed to find the problems in need of solving.

An audience member (I did not catch his name) rebutted roughly:

> In chess, we were told we could work with the computers, but a human can't
> really help a computer play chess. The computer will always win. Why do we
> think that architecture is different?

Said Jimenez: "You might be right."

---

I don't know why I am writing this. Today, I can clearly see gaps in the
models. There certainly are areas where the models fail to see the problems or
the solutions; where I find them useless in evaluating the designs that need to
be evaluated.

But then they make the rest so easy, so quick, that I feel today that I
understand less about my own code that I did as an undergrad. The code has not
become more complex. It is simply that after I say "go," I don't have to worry
about the details 75% of the time.

I don't use AI in my writing. I don't use it for this pseudonymous website. I
don't use it for writing papers to which I attach my real name. But I'll be
damned if it isn't useful sometimes in finding that segfault or generating those
matplotlib figures.

I entered into the computer architecture field because I liked the work, not
because it was secure. But the work is changing so quickly that I wonder
sometimes how much longer the joy of crafting a tight kernel or working out a
99% accurate caching heuristic can last. How much longer until the architect's
job is simply to label workloads? How much longer until the architect's job is
just to press *go*?

---

But then, as the saying goes,
> The two hardest problems in computer science are cache invalidation, naming
> things, and off-by-one-errors.

And I can say, although AI seems to be getting pretty good at naming things and
off-by-one-errors, I still struggle to get it to understand cache invalidation.
