.PHONY: images
images:
	@skopeo copy \
		docker://container-registry.oracle.com/database/free:latest \
		docker://europe-west1-docker.pkg.dev/rd-sdx-85f0/oracle-cdc/database
