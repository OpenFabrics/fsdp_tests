export TEST=/kernel/infiniband/sanity
export TESTVERSION=0.1

BUILT_FILES=

FILES=$(METADATA) runtest.sh Makefile PURPOSE tier1.sh

.PHONY: all install download clean

run: $(FILES) build
	./runtest.sh

build: $(BUILT_FILES)
	test -x runtest.sh || chmod a+x runtest.sh

clean:
	rm -f *~ $(BUILT_FILES)


include /usr/share/rhts/lib/rhts-make.include

$(METADATA): Makefile
	@echo "Owner:           Afom Michae <tmichael@redhat.com>" > $(METADATA)
	@echo "Name:            $(TEST)" >> $(METADATA)
	@echo "TestVersion:     $(TESTVERSION)" >> $(METADATA)
	@echo "Path:            $(TEST_DIR)" >> $(METADATA)
	@echo "Description:     sanity test for RDMA subsystem on OFA FSDP Cluster" >> $(METADATA)
	@echo "License:         GPLv2+" >> $(METADATA)
