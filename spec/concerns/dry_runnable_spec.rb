require 'rails_helper'

describe DryRunnable do
  class Agents::SandboxedAgent < Agent
    default_schedule '15h'

    can_dry_run!

    def check
      perform
    end

    def receive(message)
      perform(message.payload['prefix'])
    end

    private

    def perform(prefix = nil)
      log 'Logging'
      create_message payload: { 'test' => "#{prefix}foo" }
      error 'Recording error'
      create_message payload: { 'test' => "#{prefix}bar" }
      self.memory = { 'last_status' => 'ok', 'dry_run' => dry_run? }
      save!
    end
  end

  before do
    stub(Agents::SandboxedAgent).valid_type?('Agents::SandboxedAgent') { true }

    @agent = Agents::SandboxedAgent.create(name: 'some agent') { |agent|
      agent.user = users(:bob)
    }
  end

  def counts
    [users(:bob).agents.count, users(:bob).messages.count, users(:bob).logs.count]
  end

  it 'does not affect normal run, with dry_run? returning false' do
    before = counts
    after  = before.zip([0, 2, 2]).map { |x, d| x + d }

    expect {
      @agent.check
      @agent.reload
    }.to change { counts }.from(before).to(after)

    expect(@agent.memory).to eq({ 'last_status' => 'ok', 'dry_run' => false })

    payloads = @agent.messages.reorder(:id).last(2).map(&:payload)
    expect(payloads).to eq([{ 'test' => 'foo' }, { 'test' => 'bar' }])

    messages = @agent.logs.reorder(:id).last(2).map(&:message)
    expect(messages).to eq(['Logging', 'Recording error'])
  end

  it 'does not perform dry-run if Agent does not support dry-run' do
    stub(@agent).can_dry_run? { false }

    results = nil

    expect {
      results = @agent.dry_run!
      @agent.reload
    }.not_to change {
      [@agent.memory, counts]
    }

    expect(results[:log]).to match(/\A\[\d\d:\d\d:\d\d\] INFO -- : Dry Run failed\n\[\d\d:\d\d:\d\d\] ERROR -- : Exception during dry-run. SandboxedAgent does not support dry-run: /)
    expect(results[:messages]).to eq([])
    expect(results[:memory]).to eq({})
  end

  describe 'dry_run!' do
    it 'traps any destructive operations during a run' do
      results = nil

      expect {
        results = @agent.dry_run!
        @agent.reload
      }.not_to change {
        [@agent.memory, counts]
      }

      expect(results[:log]).to match(/\A\[\d\d:\d\d:\d\d\] INFO -- : Dry Run started\n\[\d\d:\d\d:\d\d\] INFO -- : Logging\n\[\d\d:\d\d:\d\d\] ERROR -- : Recording error\n/)
      expect(results[:messages]).to eq([{ 'test' => 'foo' }, { 'test' => 'bar' }])
      expect(results[:memory]).to eq({ 'last_status' => 'ok', 'dry_run' => true })
    end

    it 'traps any destructive operations during a run when an message is given' do
      results = nil

      expect {
        results = @agent.dry_run!(Message.new(payload: { 'prefix' => 'super' }))
        @agent.reload
      }.not_to change {
        [@agent.memory, counts]
      }

      expect(results[:log]).to match(/\A\[\d\d:\d\d:\d\d\] INFO -- : Dry Run started\n\[\d\d:\d\d:\d\d\] INFO -- : Logging\n\[\d\d:\d\d:\d\d\] ERROR -- : Recording error\n/)
      expect(results[:messages]).to eq([{ 'test' => 'superfoo' }, { 'test' => 'superbar' }])
      expect(results[:memory]).to eq({ 'last_status' => 'ok', 'dry_run' => true })
    end
  end
end
