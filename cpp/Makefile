CXX=g++
INCLUDES=-Iinclude
CXXFLAGS=-O2 -Wall $(INCLUDES) $(shell pkg-config --cflags libxml++-2.6) $(shell pkg-config --cflags libpqxx)
LIBS=$(shell pkg-config --libs libxml++-2.6) $(shell pkg-config --libs libpqxx) -lboost_program_options
TEST_LIBS=-lboost_unit_test_framework

SRCS=\
	src/osm/data/document.cpp \
	src/osm/data/element.cpp \
	src/osm/data/node.cpp \
	src/osm/data/relation.cpp \
	src/osm/data/way.cpp \
	src/osm/db/dupe_nodes.cpp \
	src/osm/db/owl_database.cpp \
	src/osm/db/owl_diff.cpp \
	src/osm/db/owl_diff/attributes.cpp \
	src/osm/db/owl_diff/change.cpp \
	src/osm/db/owl_diff/element.cpp \
	src/osm/db/owl_diff/node.cpp \
	src/osm/db/owl_diff/way.cpp \
	src/osm/db/owl_diff/relation.cpp \
	src/osm/db/owl_diff/tiler.cpp \
	src/osm/db/owl_loader.cpp \
	src/osm/io/api_database.cpp \
	src/osm/io/database.cpp \
	src/osm/io/document.cpp \
	src/osm/io/xml_document_reader.cpp \
	src/osm/member.cpp \
	src/osm/util/lcs.cpp

TEST_SRCS=\
	src/test/util/lcs.cpp \
	src/test/util/quad_tile.cpp \
	src/test/owl_diff/test_tiler.cpp

OBJS=$(SRCS:src/%.cpp=obj/%.o)
TEST_OBJS=$(TEST_SRCS:src/%.cpp=obj/%.o)
DEPDIR = .deps
DEPF = $(DEPDIR)/$*
MAKEDEPEND = $(CXX) -MM $(CXXFLAGS) -o $(DEPF).d $<

all: $(OBJS)

clean:
	rm -rf $(DEPDIR) $(OBJS) $(TEST_OBJS) tests main

obj/%.o : src/%.cpp
	@mkdir -p $(DEPDIR)/$(*D); \
	$(MAKEDEPEND); \
        cp $(DEPF).d $(DEPF).P; \
#	sed -e 's/#.*//' -e 's/^[^:]*: *//' -e 's/ *\\$$//' \
#	    -e '/^$$/ d' -e 's/$$/ :/' < $(DEPF).d >> $(DEPF).P; \
	rm -f $(DEPF).d
	@mkdir -p $(@D)
	$(CXX) $(CXXFLAGS) -o $@ -c $<

tests: src/test/main.cpp $(TEST_OBJS) $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LIBS) $(TEST_LIBS)

test_lcs: test_lcs.cpp src/osm/util/lcs.o
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LIBS)

test_diff: test_diff.cpp $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LIBS)

test_db: test_db.cpp $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LIBS)

main: src/main.cpp $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LIBS)

dupe_daemon: src/dupe_daemon.cpp $(OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LIBS)

list-deps:
	@echo $(SRCS:src/%.cpp=$(DEPDIR)/%.P)

-include $(SRCS:src/%.cpp=$(DEPDIR)/%.P)

