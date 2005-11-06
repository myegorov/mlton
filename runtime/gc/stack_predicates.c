/* Copyright (C) 1999-2005 Henry Cejtin, Matthew Fluet, Suresh
 *    Jagannathan, and Stephen Weeks.
 * Copyright (C) 1997-2000 NEC Research Institute.
 *
 * MLton is released under a BSD-style license.
 * See the file MLton-LICENSE for details.
 */

bool isStackEmpty (GC_stack stack) {
  return 0 == stack->used;
}

#if ASSERT
bool isStackReservedAligned (GC_state s, size_t reserved) {
  return isAligned (GC_STACK_HEADER_SIZE + sizeof (struct GC_stack) + reserved, 
                    s->alignment);
}
#endif

