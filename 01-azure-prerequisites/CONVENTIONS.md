# Conventions

## Resource Naming Prefix

Resources managed with this example stacks are prefixed with a name fragment like `vmazex` (*v*anilla - *m*ft - on *az*ure - *ex*ample). `vmazex` is the default value for the prefix on all stacks, but the user is expected to give their own when using the example.

The prefix helps us keep together all stacks of a project. It must be short and a combination of lower case letters.

First letter identify the type of environment:

- d - development
- v - vanilla (our default in the example)
- e - pre-production
- p - production
- t - test

The rest of the letters must be as unique as possible in the global landscape, e.g. akfjs
example prefixes: vakfjs, dplexh
