module Jobs
  class CheckLotteries < ::Jobs::Scheduled
    every 1.minute

    def execute(args)
      running_lotteries = Lottery.running
      return if running_lotteries.empty?

      running_lotteries.find_each do |lottery|
        begin
          should_draw = if lottery.by_time? && lottery.draw_at
                          Time.zone.now >= lottery.draw_at
                        elsif lottery.by_reply? && lottery.draw_reply_count
                          lottery.topic.posts_count - 1 >= lottery.draw_reply_count
                        else
                          false
                        end
          
          if should_draw
            LotteryManager.new(lottery).perform_draw
          end
        rescue => e
          Rails.logger.error("LOTTERY_DRAW_ERROR: Failed to process lottery ##{lottery.id} for topic ##{lottery.topic_id}. Error: #{e.class.name}: #{e.message}\n#{e.backtrace.join("\n")}")
        end
      end
    end
  end
end
