module Jobs
  class CheckLotteries < ::Jobs::Scheduled
    every 1.minute

    def execute(args)
      Lottery.running.where("draw_at <= ?", Time.zone.now).find_each do |lottery|
        begin
          LotteryManager.new(lottery).perform_draw
        rescue => e
          Rails.logger.error("LOTTERY_DRAW_ERROR: Failed to process lottery ##{lottery.id}. Error: #{e.class.name}: #{e.message}")
        end
      end
    end
  end
end
