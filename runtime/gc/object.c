/* Copyright (C) 1999-2005 Henry Cejtin, Matthew Fluet, Suresh
 *    Jagannathan, and Stephen Weeks.
 * Copyright (C) 1997-2000 NEC Research Institute.
 *
 * MLton is released under a BSD-style license.
 * See the file MLton-LICENSE for details.
 */

const char* objectTypeTagToString (GC_objectTypeTag tag) {
  switch (tag) {
  case ARRAY_TAG:
    return "ARRAY";
  case NORMAL_TAG:
    return "NORMAL";
  case STACK_TAG:
    return "STACK";
  case WEAK_TAG:
    return "WEAK";
  default:
    die ("bad GC_objectTypeTag %u", tag);
  }
}

/* getHeaderp (p)
 *
 * Returns a pointer to the header for the object pointed to by p.
 */
GC_header* getHeaderp (pointer p) {
  return (GC_header*)(p 
                      - GC_HEADER_SIZE);
}

/* getHeader (p) 
 *
 * Returns the header for the object pointed to by p. 
 */
GC_header getHeader (pointer p) {
  return *(getHeaderp(p));
}

/*
 * Build the header for an object, given the index to its type info.
 */
GC_header buildHeaderFromTypeIndex (uint32_t t) {
  assert (t < TWOPOWER (TYPE_INDEX_BITS));
  return 1 | (t << 1);
}

void splitHeader(GC_state s, GC_header header,
                 GC_objectTypeTag *tagRet, bool *hasIdentityRet,
                 uint16_t *numNonObjptrsRet, uint16_t *numObjptrsRet) {
  unsigned int objectTypeIndex; 
  GC_objectType objectType; 
  GC_objectTypeTag tag;
  bool hasIdentity;
  uint16_t numNonObjptrs, numObjptrs;

  assert (1 == (header & GC_VALID_HEADER_MASK)); 
  objectTypeIndex = (header & TYPE_INDEX_MASK) >> TYPE_INDEX_SHIFT; 
  assert (objectTypeIndex < s->objectTypesLength); 
  objectType = &s->objectTypes [objectTypeIndex]; 
  tag = objectType->tag; 
  hasIdentity = objectType->hasIdentity; 
  numNonObjptrs = objectType->numNonObjptrs; 
  numObjptrs = objectType->numObjptrs; 

  if (DEBUG_DETAILED) 
    fprintf (stderr, 
             "splitHeader ("FMTHDR")" 
             "  tag = %s" 
             "  hasIdentity = %s" 
             "  numNonObjptrs = %"PRIu16 
             "  numObjptrs = %"PRIu16"\n", 
             header, 
             objectTypeTagToString(tag), 
             boolToString(hasIdentity), 
             numNonObjptrs, numObjptrs); 

  if (tagRet != NULL)
    *tagRet = tag;
  if (hasIdentityRet != NULL)
    *hasIdentityRet = hasIdentity;
  if (numNonObjptrsRet != NULL)
    *numNonObjptrsRet = numNonObjptrs;
  if (numObjptrsRet != NULL)
    *numObjptrsRet = numObjptrs;
}

pointer alignFrontier (GC_state s, pointer p) {
  size_t res;

  res = pad (s, (size_t)p, GC_NORMAL_HEADER_SIZE);
  if (DEBUG_STACKS)
    fprintf (stderr, FMTPTR" = alignFrontier ("FMTPTR")\n", 
             (uintptr_t)p, (uintptr_t)res);
  assert (isFrontierAligned (s, (pointer)res));
  return (pointer)res;
}

/* advanceToObjectData (s, p)
 *
 * If p points at the beginning of an object, then advanceToObjectData
 * returns a pointer to the start of the object data.
 */
pointer advanceToObjectData (GC_state s, pointer p) {
  GC_header header;
  pointer res;

  assert (isFrontierAligned (s, p));
  header = *(GC_header*)p;
  if (0 == header)
    /* Looking at the counter word in an array. */
    res = p + GC_ARRAY_HEADER_SIZE;
  else
    /* Looking at a header word. */
    res = p + GC_NORMAL_HEADER_SIZE;
  assert (isAligned ((uintptr_t)res, s->alignment));
  return res;
}
