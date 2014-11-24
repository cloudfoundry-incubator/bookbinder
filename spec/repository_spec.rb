require 'spec_helper'

module Bookbinder
  describe Repository do
    include_context 'tmp_dirs'

    let(:logger) { NilLogger.new }
    let(:github_token) { 'blahblah' }
    let(:git_client) { GitClient.new(logger, access_token: github_token) }
    let(:github) {"https://#{ENV['GITHUB_API_TOKEN']}:x-oauth-basic@github.com"}

    before do
      allow(GitClient).to receive(:new).and_call_original
      allow(GitClient).to receive(:new).with(logger, access_token: github_token).and_return(git_client)
      allow_any_instance_of(Repository).to receive(:get_repo_url) { |o, name | "#{github}/#{name}"}
    end

    it 'requires a full_name' do
      expect {
        Repository.new(logger: logger, github_token: github_token, full_name: '')
      }.not_to raise_error

      expect {
        Repository.new(logger: logger, github_token: github_token)
      }.to raise_error(/full_name/)
    end

    describe '#tag_with' do
      let(:head_sha) { 'ha7f'*10 }

      it 'calls #create_tag! on the github instance variable' do
        expect(git_client).to receive(:head_sha).with('org/repo').and_return head_sha
        expect(git_client).to receive(:create_tag!).with('org/repo', 'the_tag_name', head_sha)

        Repository.new(logger: logger, github_token: github_token, full_name: 'org/repo').tag_with('the_tag_name')
      end
    end

    describe '#short_name' do
      it 'returns the repo name when org and repo name are provided' do
        expect(Repository.new(full_name: 'some-org/some-name').short_name).to eq('some-name')
      end
    end

    describe '#head_sha' do
      let(:github_token) { 'my_token' }

      it "returns the first (most recent) commit's sha if @head_sha is unset" do
        fake_github = double(:github)

        expect(GitClient).to receive(:new).
                                 with(logger, access_token: github_token).
                                 and_return(fake_github)

        expect(fake_github).to receive(:head_sha).with('org/repo').and_return('dcba')

        repository = Repository.new(logger: logger, full_name: 'org/repo', github_token: github_token)
        expect(repository.head_sha).to eq('dcba')
      end
    end

    describe '#directory' do
      it 'returns @directory if set' do
        expect(Repository.new(full_name: '', directory: 'the_directory').directory).to eq('the_directory')
      end

      it 'returns #short_name if @directory is unset' do
        expect(Repository.new(full_name: 'org/repo').directory).to eq('repo')
      end
    end

    describe '#copy_from_remote' do
      let(:repo_name) { 'org/my-docs-repo' }
      let(:target_ref) { 'some-sha' }
      let(:repo) { Repository.new(logger: logger, full_name: repo_name, target_ref: target_ref, github_token: 'foo') }
      let(:destination_dir) { tmp_subdir('destination') }
      let(:git_base_object) { double Git::Base }
      let(:clone) {
        expect(Git).to receive(:clone).with("#{github}/#{repo_name}", File.basename(repo_name),
                                            path: destination_dir).and_return(git_base_object)
      }

      it 'retrieves the repo from github' do
        clone
        expect(git_base_object).to receive(:checkout).with(target_ref)
        repo.copy_from_remote(destination_dir)
      end

      context 'when the target ref is master' do
        let(:target_ref) { 'master' }
        it 'does not check out a ref' do
          clone
          expect(git_base_object).to_not receive(:checkout)
          repo.copy_from_remote(destination_dir)
        end
      end

      context 'when the target ref is not master' do
        it 'checks out a ref' do
          clone
          expect(git_base_object).to receive(:checkout).with(target_ref)
          repo.copy_from_remote(destination_dir)
        end
      end

      it 'returns the location of the copied directory' do
        clone
        expect(git_base_object).to receive(:checkout).with(target_ref)
        expect(repo.copy_from_remote(destination_dir)).to eq(destination_dir)
      end

      it 'sets copied? to true' do
        clone
        expect(git_base_object).to receive(:checkout).with(target_ref)
        expect { repo.copy_from_remote(destination_dir) }.to change { repo.copied? }.to(true)
      end
    end

    describe '#copy_from_local' do
      let(:full_name) { 'org/my-docs-repo' }
      let(:target_ref) { 'some-sha' }
      let(:local_repo_dir) { tmp_subdir 'local_repo_dir' }
      let(:repo) { Repository.new(logger: logger, full_name: full_name, target_ref: target_ref, local_repo_dir: local_repo_dir) }
      let(:destination_dir) { tmp_subdir('destination') }
      let(:repo_dir) { File.join(local_repo_dir, 'my-docs-repo') }
      let(:copy_to) { repo.copy_from_local destination_dir }

      context 'and the local repo is there' do
        before do
          Dir.mkdir repo_dir
          FileUtils.touch File.join(repo_dir, 'my_aunties_goat.txt')
        end

        it 'returns true' do
          expect(copy_to).to eq(File.join(destination_dir, 'my-docs-repo'))
        end

        it 'copies the repo' do
          copy_to
          expect(File.exist? File.join(destination_dir, 'my-docs-repo', 'my_aunties_goat.txt')).to eq(true)
        end

        it 'sets copied? to true' do
          expect { copy_to }.to change { repo.copied? }.to(true)
        end
      end

      context 'and the local repo is not there' do
        it 'should not find the directory' do
          expect(File.exist? repo_dir).to eq(false)
        end

        it 'returns false' do
          expect(copy_to).to be_nil
        end

        it 'does not change copied?' do
          expect { copy_to }.not_to change { repo.copied? }
        end
      end
    end

    describe '#has_tag?' do
      let(:repo) { Repository.new(full_name: 'my-docs-org/my-docs-repo',
                                  target_ref: 'some_sha',
                                  directory: 'pretty_url_path',
                                  local_repo_dir: '') }
      let(:my_tag) { '#hashtag' }

      before do
        allow(GitClient).to receive(:new).and_return(git_client)
        allow(git_client).to receive(:tags).and_return(tags)
      end

      context 'when a tag has been applied' do
        let(:tags) do
          [OpenStruct.new(name: my_tag)]
        end

        it 'is true when checking that tag' do
          expect(repo).to have_tag(my_tag)
        end
        it 'is false when checking a different tag' do
          expect(repo).to_not have_tag('nobody_uses_me')
        end
      end

      context 'when no tag has been applied' do
        let(:tags) { [] }

        it 'is false' do
          expect(repo).to_not have_tag(my_tag)
        end
      end
    end

    describe '#tag_with' do
      let(:repo_sha) { 'some-sha' }
      let(:repo) { Repository.new(logger: logger,
                                  github_token: github_token,
                                  full_name: 'my-docs-org/my-docs-repo',
                                  target_ref: repo_sha,
                                  directory: 'pretty_url_path',
                                  local_repo_dir: '') }
      let(:my_tag) { '#hashtag' }

      before do
        allow(git_client).to receive(:validate_authorization)
        allow(git_client).to receive(:commits).with(repo.full_name)
                             .and_return([OpenStruct.new(sha: repo_sha)])
      end

      it 'should apply a tag' do
        expect(git_client).to receive(:create_tag!)
                              .with(repo.full_name, my_tag, repo_sha)

        repo.tag_with(my_tag)
      end
    end

    describe '#update_local_copy' do
      let(:local_repo_dir) { tmpdir }
      let(:full_name) { 'org/repo-name' }
      let(:repo_dir) { File.join(local_repo_dir, 'repo-name') }
      let(:repository) { Repository.new(logger: logger, github_token: github_token, full_name: full_name, local_repo_dir: local_repo_dir) }

      context 'when the repo dirs are there' do
        before do
          Dir.mkdir repo_dir
        end

        it 'issues a git pull in each repo' do
          expect(Kernel).to receive(:system).with("cd #{repo_dir} && git pull")
          repository.update_local_copy
        end
      end

      context 'when a repo is not there' do
        it 'does not attempt a git pull' do
          expect(Kernel).to_not receive(:system)
          repository.update_local_copy
        end
      end
    end

    describe '#copy_from_remote' do
      let(:full_name) { 'org/my-docs-repo' }
      let(:target_ref) { 'arbitrary-reference' }
      let(:made_up_dir) { 'this/doesnt/exist' }
      let(:git_base_object) { double Git::Base }
      let(:repo) do
        Repository.new(logger: logger, github_token: github_token, full_name: full_name, target_ref: target_ref)
      end

      context 'when no special Git accessor is specified' do
        it 'clones the repo into a specified folder' do
          expect(Git).to receive(:clone).with("#{github}/#{full_name}",
                                              File.basename(full_name),
                                              path: made_up_dir).and_return(git_base_object)
          expect(git_base_object).to receive(:checkout).with(target_ref)
          repo.copy_from_remote(made_up_dir)
        end
      end

      context 'when using a special Git accessor' do
        before do
          class MyGitClass
            def self.clone(arg1, arg2, path: nil)
              #do nothing
            end
          end
        end

        it 'clones using the specified accessor' do
          expect(MyGitClass).to receive(:clone).with("#{github}/#{full_name}",
                                                     File.basename(full_name),
                                                     path: made_up_dir).and_return(git_base_object)
          expect(git_base_object).to receive(:checkout).with(target_ref)
          repo.copy_from_remote(made_up_dir, MyGitClass)
        end
      end
    end

    describe '#get_modification_date_for' do
      let(:repo_name) { 'org/my-docs-repo' }
      let(:target_ref) { 'some-sha' }
      let(:repo) { Repository.new(logger: logger, full_name: repo_name, target_ref: target_ref, github_token: 'foo') }
      let(:destination_dir) { tmp_subdir('destination') }
      let(:git_base_object) { double Git::Base }
      let(:git_history) { double Git::Log }
      let(:git_history_most_recent_entry) { double Git::Log }
      let(:most_recent_commit) { double Git::Object::Commit }

      before do
        allow(Git).to receive(:clone).and_return(git_base_object)
      end

      context 'if the git accessor is nil' do
        let(:git_base_object) { nil }
        it 'raises' do
          expect{ repo.get_modification_date_for(file: 'path/file.html', git: nil) }.
              to raise_error(/Unexpected Error: Git accessor unavailable/)
        end
      end


      context 'if the git accessor exists' do
        before do
          allow(git_base_object).to receive(:checkout).with(target_ref)
          allow(git_base_object).to receive(:log).with(1).and_return(git_history)
        end

        context 'and when the file exists' do
          it 'returns the most recent modification date' do
            some_time = Time.now

            allow(git_history).to receive(:object).with('path/file.html').and_return(git_history_most_recent_entry)
            allow(git_history_most_recent_entry).to receive(:first).and_return most_recent_commit
            allow(most_recent_commit).to receive(:date).and_return some_time

            repo.copy_from_remote(destination_dir)

            expect(repo.get_modification_date_for(file: 'path/file.html')).to eq(some_time)
          end
        end

        context 'when the file does not exist or is not tracked by git' do
          it 'raises an error to the user' do
            allow(git_history).to receive(:object).with('does/not/exist.html').and_return(git_history_most_recent_entry)
            allow(git_history_most_recent_entry).to receive(:first).and_return most_recent_commit
            allow(most_recent_commit).to receive(:date).and_raise(Git::GitExecuteError)

            repo.copy_from_remote(destination_dir)
            expect{repo.get_modification_date_for(file: 'does/not/exist.html')}.
                to raise_error(/This file does not exist or is not tracked by git!/)
          end
        end
      end
    end
  end
end
