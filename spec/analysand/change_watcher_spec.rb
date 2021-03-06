require 'spec_helper'

require 'analysand/change_watcher'
require 'analysand/database'
require 'celluloid'

module Analysand
  describe ChangeWatcher do
    class TestWatcher < Analysand::ChangeWatcher
      attr_accessor :changes

      def initialize(database, credentials)
        super(database)

        self.changes = []

        @credentials = credentials
      end

      def customize_request(req)
        req.basic_auth(@credentials[:username], @credentials[:password])
      end

      def process(change)
        changes << change
        change_processed(change)
      end
    end

    let(:db) { Database.new(database_uri) }

    before do
      create_databases!
    end

    after do
      Celluloid.shutdown

      drop_databases!
    end

    describe '#connection_ok' do
      describe 'with a non-public change feed' do
        before do
          set_security({ 'names' => [admin_username] })
        end

        after do
          clear_security
        end

        it 'passes credentials' do
          watcher = TestWatcher.new(db, admin_credentials)

          expect(watcher.connection_ok).to eq(true)
        end
      end
    end

    describe '#changes_feed_uri' do
      let!(:watcher) { TestWatcher.new(db, admin_credentials) }

      describe 'when invoked multiple times' do
        it 'returns what it returned the first time' do
          uri1 = watcher.changes_feed_uri
          uri2 = watcher.changes_feed_uri

          uri1.should == uri2
        end
      end
    end

    describe '#waiter_for' do
      let!(:watcher) { TestWatcher.new(db, admin_credentials) }

      describe 'if the given document has not been processed' do
        it 'blocks until the document has been processed' do
          waiter = watcher.waiter_for('bar')

          Thread.new do
            db.put('foo', { 'foo' => 'bar' }, admin_credentials)
            db.put('bar', { 'foo' => 'bar' }, admin_credentials)
          end

          waiter.wait

          watcher.changes.detect { |r| r['id'] == 'foo' }.should_not be_nil
        end
      end
    end

    it 'receives changes' do
      watcher = TestWatcher.new(db, admin_credentials)

      waiter = watcher.waiter_for('foo')
      db.put('foo', { 'foo' => 'bar' }, admin_credentials)
      waiter.wait

      expect(watcher.changes.select { |r| r['id'] == 'foo' }.length).to eq(1)
    end
  end
end
