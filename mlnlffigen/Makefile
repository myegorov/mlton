## Copyright (C) 2005-2009 Henry Cejtin, Matthew Fluet, Suresh
 #    Jagannathan, and Stephen Weeks.
 #
 # MLton is released under a BSD-style license.
 # See the file MLton-LICENSE for details.
 ##

SRC := $(shell cd .. && pwd)
BUILD := $(SRC)/build
BIN := $(BUILD)/bin
LIB := $(BUILD)/lib/mlton
MLTON := mlton
TARGET := self
FLAGS := -target $(TARGET) -default-ann 'sequenceNonUnit warn'
NAME := mlnlffigen
PATH := $(BIN):$(shell echo $$PATH)

all:	$(NAME)

cppcmd.sml : gen-cppcmd
	./gen-cppcmd > $@

$(NAME): $(NAME).mlb $(shell PATH="$(BIN):$$PATH" && "$(MLTON)" -stop f $(NAME).mlb)
	@echo 'Compiling $(NAME)'
	$(MLTON) $(FLAGS) $(NAME).mlb

.PHONY: clean
clean:
	../bin/clean
