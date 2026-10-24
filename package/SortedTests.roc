import Sorted

## Tests of `Sorted`. Run with `roc test package/SortedTests.roc`.
SortedTests :: {}.{}

expect Sorted.unique([]) == []
expect Sorted.unique([7]) == [7]
expect Sorted.unique([1, 1, 2, 5, 5, 5]) == [1, 2, 5]
expect Sorted.unique([9, 9, 4, 0, 0]) == [0, 4, 9]
expect Sorted.unique([3, 1, 2, 3, 0, 9, 1, 8, 2]) == [0, 1, 2, 3, 8, 9]
expect Sorted.unique([5, 5, 5]) == [5]
expect Sorted.unique([2, 1, 3]) == [1, 2, 3]
