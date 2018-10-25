type
  BFCore* = ref object
   memory*: array[1024, uint8]
   pc*, ap*: int
