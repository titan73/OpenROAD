/*******************************************************************************
 *******************************************************************************
 * Copyright 2014, Cadence Design Systems
 *
 * This  file  is  part  of  the  Cadence  LEF/DEF  Open   Source
 * Distribution,  Product Version 5.8.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 *    you may not use this file except in compliance with the License.
 *    You may obtain a copy of the License at
 *
 *        http://www.apache.org/licenses/LICENSE-2.0
 *
 *    Unless required by applicable law or agreed to in writing, software
 *    distributed under the License is distributed on an "AS IS" BASIS,
 *    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
 *    implied. See the License for the specific language governing
 *    permissions and limitations under the License.
 *
 * For updates, support, or to become part of the LEF/DEF Community,
 * check www.openeda.org for details.
 *******************************************************************************
 ******************************************************************************/

#include <sys/stat.h>
#include <sys/types.h>

#include <climits>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "lefrReader.h"
#include "lefzlib.h"
#include "zlib.h"

/*
 * Private functions:
 */
size_t lefGZip_read(FILE* file, char* buf, size_t len)
{
  return gzread((gzFile) file, buf, (unsigned int) len);
}

/*
 * Public functions:
 */
lefGZFile lefGZipOpen(const char* gzipPath, const char* mode)
{
  lefGZFile fptr;

  if (!gzipPath) {
    return NULL;
  }

  fptr = gzopen(gzipPath, mode);

  if (fptr) {
    /* successfully open the gzip file */
    /* set the read function to read from a compressed file */
    lefrSetReadFunction(lefGZip_read);
    return (lefGZFile) fptr;
  } else {
    return NULL;
  }
}

int lefGZipClose(lefGZFile filePtr)
{
  return (gzclose((gzFile) filePtr));
}

int lefrReadGZip(lefGZFile file, const char* gzipFile, lefiUserData uData)
{
  return lefrRead((FILE*) file, gzipFile, uData);
}
