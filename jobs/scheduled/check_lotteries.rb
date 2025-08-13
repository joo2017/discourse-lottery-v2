module Jobs
  class CheckLotteries < ::Jobs::Scheduled
    every 1.minute

    def execute(args)
      # 使用常量来查询所有“进行中”的抽奖
      Lottery.where(status: Lottery::STATUSES[:running]).find_each do |lottery|
        # 使用常量进行比较
        if (lottery.draw_type == Lottery::DRAW_TYPES[:by_time] && Time.now >= lottery.draw_at) ||
           (lottery.draw_type == Lottery::DRAW_TYPES[:by_reply] && lottery.topic.posts_count - 1 >= lottery.draw_reply_count)
          
          LotteryManager.new(lottery).perform_draw
        end
      end
    end
  end
end
