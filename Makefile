.PHONY: lock lock-conservative lock-all lock-all-conservative

# Generate/update all lockfiles using appropriate Ruby versions via Docker
# Usage:
#   make lock              - Full lock update (may upgrade gems)
#   make lock-conservative - Conservative update (only add new gems)

DOCKER_RUN = docker run --rm -v "$(CURDIR)":/app -w /app

lock: lock-default lock-rails-5.2 lock-rails-6.1 lock-rails-7.2 lock-rails-8.0

lock-conservative: lock-default-conservative lock-rails-5.2-conservative lock-rails-6.1-conservative lock-rails-7.2-conservative lock-rails-8.0-conservative

lock-default:
	bundle lock --update

lock-default-conservative:
	bundle lock --conservative

lock-rails-5.2:
	$(DOCKER_RUN) ruby:2.7 bash -c "BUNDLE_GEMFILE=gemfiles/Gemfile.rails-5.2 bundle lock --update"

lock-rails-5.2-conservative:
	$(DOCKER_RUN) ruby:2.7 bash -c "BUNDLE_GEMFILE=gemfiles/Gemfile.rails-5.2 bundle lock --conservative"

lock-rails-6.1:
	$(DOCKER_RUN) ruby:3.1 bash -c "BUNDLE_GEMFILE=gemfiles/Gemfile.rails-6.1 bundle lock --update"

lock-rails-6.1-conservative:
	$(DOCKER_RUN) ruby:3.1 bash -c "BUNDLE_GEMFILE=gemfiles/Gemfile.rails-6.1 bundle lock --conservative"

lock-rails-7.2:
	BUNDLE_GEMFILE=gemfiles/Gemfile.rails-7.2 bundle lock --update

lock-rails-7.2-conservative:
	BUNDLE_GEMFILE=gemfiles/Gemfile.rails-7.2 bundle lock --conservative

lock-rails-8.0:
	BUNDLE_GEMFILE=gemfiles/Gemfile.rails-8.0 bundle lock --update

lock-rails-8.0-conservative:
	BUNDLE_GEMFILE=gemfiles/Gemfile.rails-8.0 bundle lock --conservative
