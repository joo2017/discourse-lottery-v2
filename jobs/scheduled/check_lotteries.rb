module Jobs
  class CheckLotteries < ::Jobs::Scheduled
    every 1.minute

    def execute(args)
      Lottery.running.find_each do |lottery|
        if (lottery.by_time? && Time.now >= lottery.draw_at) ||
           (lottery.by_reply? && lottery.topic.posts_count - 1 >= lottery.draw_reply_count)
          
          LotteryManager.new(lottery).perform_draw
        end
      end
    end
  end
end
