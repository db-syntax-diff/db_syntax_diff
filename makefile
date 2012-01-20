#############################################################################
#  Copyright (C) 2008-2010 NTT
#############################################################################

SRC_DIR=./
LIB_DIR            = $(SRC_DIR)/lib/PgSqlExtract
ANALYZER_DIR       = $(LIB_DIR)/Analyzer
INPUTANALYZER_DIR  = $(LIB_DIR)/InputAnalyzer
CPARSER_PM         = $(ANALYZER_DIR)/CParser.pm
CPARSER_YP         = $(ANALYZER_DIR)/CParser.yp
CPARSER_OUT        = $(ANALYZER_DIR)/CParser.output
JAVAPARSER_PM      = $(INPUTANALYZER_DIR)/JavaParser.pm
JAVAPARSER_YP      = $(INPUTANALYZER_DIR)/JavaParser.yp
JAVAPARSER_OUT     = $(INPUTANALYZER_DIR)/JavaParser.output
DOC_DIR            = ./docs
PROJECT_DOC_DIR    = ./docs_project

all: yapp

yapp:
	yapp -n -m PgSqlExtract::InputAnalyzer::JavaParser -o $(JAVAPARSER_PM) -v $(JAVAPARSER_YP) ;\
	yapp -n -m PgSqlExtract::Analyzer::CParser -o $(CPARSER_PM) -v $(CPARSER_YP)

docs: clean
	mkdir docs docs_project; \
	grep -v ^#! $(JAVAPARSER_YP) > $(JAVAPARSER_PM); \
	NaturalDocs -i $(SRC_DIR) -o FramedHTML $(DOC_DIR) -p $(PROJECT_DOC_DIR); \
	rm -rf $(JAVAPARSER_PM)

clean:
	rm -rf docs docs_project dist $(JAVAPARSER_PM) $(JAVAPARSER_OUT) $(CPARSER_PM) $(CPARSER_OUT)

cleanall: clean
	rm -rf DD.zip pg_sqlextract_j.tar.gz

dist: docs
	mkdir dist; \
	cd dist; \
	sed 's/SRC_DIR            = \.\/src/SRC_DIR=.\//' ../makefile >makefile ; \
	mkdir bin config lib; \
	mkdir lib/PgSqlExtract; \
	mkdir lib/PgSqlExtract/Common; \
	mkdir lib/PgSqlExtract/ExpressionAnalyzer; \
	mkdir lib/PgSqlExtract/InputAnalyzer; \
	mkdir lib/PgSqlExtract/Analyzer; \
	cp ../config/*.xml config; \
	cp ../src/*.pl bin; \
	cp ../src/lib/PgSqlExtract/*.pm lib/PgSqlExtract; \
	cp ../src/lib/PgSqlExtract/Common/*.pm lib/PgSqlExtract/Common; \
	cp ../src/lib/PgSqlExtract/ExpressionAnalyzer/*.pm lib/PgSqlExtract/ExpressionAnalyzer; \
	cp ../src/lib/PgSqlExtract/InputAnalyzer/*.pm lib/PgSqlExtract/InputAnalyzer; \
	cp ../src/lib/PgSqlExtract/Analyzer/*.pm lib/PgSqlExtract/Analyzer; \
	cp ../src/lib/PgSqlExtract/InputAnalyzer/*.yp lib/PgSqlExtract/InputAnalyzer; \
	cp ../src/lib/PgSqlExtract/Analyzer/*.yp lib/PgSqlExtract/Analyzer; \
	tar cvzf pg_sqlextract_j.tar.gz bin config lib makefile ; \
	cp pg_sqlextract_j.tar.gz ..; \
	cd ..; \
	cd docs; \
	zip -r DD *; \
	cp DD.zip ..
