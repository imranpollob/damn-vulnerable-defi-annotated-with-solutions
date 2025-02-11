## Step to follow

```bash
forge install

forge build

forge test 

--match-test <REGEX>
          Only run test functions matching the specified regex pattern
          
          [aliases: mt]
--match-contract <REGEX>
          Only run tests in contracts matching the specified regex pattern
          
          [aliases: mc]
--match-path <GLOB>
          Only run tests in source files matching the specified glob pattern
          
          [aliases: mp]

forge test --mc UnstoppableChallenge -vvvv
```