Mike to Shaw: You asked a good question about negative testing at the meeting.  I had a raft of examples from earlier that I didn't bring up.  Here are some:

- that `temper publish --dry-run` does not actually send anything upstream
- that `temper build --offline` does not do network fetches
- that the compiler doesn't do locale sensitive case comparisons internally, e.g. that running the compiler with LC_*=tr_TR doesn't affect behaviour
- that http imports do not ignore robots.txt
- that `temper publish` does not produce bundles that link against test-only dependencies

These kinds of things are not terribly hard to spot check for, but harder to enforce.  But sometimes there are testing strategies.  For example, to test network connections, you can run processes with syscalls instrumented or inside `proxychains` to understand what files are being accessed and what network traffic is happening.  I'd like us to look for these opportunities so that we can rely more on closed-box testing strategies.
