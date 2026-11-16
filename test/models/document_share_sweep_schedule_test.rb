require "test_helper"

# Expired share links are cleared every night in production, by the command
# Solid Queue's schedule names.
class DocumentShareSweepScheduleTest < ActiveSupport::TestCase
  test "the nightly schedule runs a command that deletes expired links" do
    task = YAML.load_file(Rails.root.join("config/recurring.yml")).dig("production", "sweep_expired_share_links")
    assert task, "scheduled in production"
    assert_match(/every day/, task["schedule"])

    org   = organizations(:one)
    ar    = Plutus::Asset.create!(tenant: org, name: "AR", code: "1200")
    sales = Plutus::Revenue.create!(tenant: org, name: "Sales", code: "4100")
    create_invoice(org, client_name: "Acme", amount: 100, receivable: ar, revenue: sales).start_sharing!
    travel(1.year + 1.day) do
      assert_difference -> { DocumentShare.count }, -1 do
        eval(task["command"]) # rubocop:disable Security/Eval -- the schedule's own command, as Solid Queue runs it
      end
    end
  end
end
