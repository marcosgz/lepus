.PHONY: lock lock-conservative

DOCKER_RUN = docker run --rm -v "$(CURDIR)":/app -w /app

# Update all lockfiles (conservative - only add new gems, no upgrades)
lock-conservative:
	$(DOCKER_RUN) ruby:2.7 bash -c "gem install bundler:2.3.22 && bundle lock --conservative"
	$(DOCKER_RUN) ruby:2.7 bash -c "gem install bundler:2.3.22 && BUNDLE_GEMFILE=gemfiles/Gemfile.rails-5.2 bundle lock --conservative"
	$(DOCKER_RUN) ruby:3.1 bash -c "BUNDLE_GEMFILE=gemfiles/Gemfile.rails-6.1 bundle lock --conservative"
	BUNDLE_GEMFILE=gemfiles/Gemfile.rails-7.2 bundle lock --conservative
	BUNDLE_GEMFILE=gemfiles/Gemfile.rails-8.0 bundle lock --conservative

# Update all lockfiles (full update - may upgrade gems)
lock:
	$(DOCKER_RUN) ruby:2.7 bash -c "gem install bundler:2.3.22 && bundle lock --update"
	$(DOCKER_RUN) ruby:2.7 bash -c "gem install bundler:2.3.22 && BUNDLE_GEMFILE=gemfiles/Gemfile.rails-5.2 bundle lock --update"
	$(DOCKER_RUN) ruby:3.1 bash -c "BUNDLE_GEMFILE=gemfiles/Gemfile.rails-6.1 bundle lock --update"
	BUNDLE_GEMFILE=gemfiles/Gemfile.rails-7.2 bundle lock --update
	BUNDLE_GEMFILE=gemfiles/Gemfile.rails-8.0 bundle lock --update
