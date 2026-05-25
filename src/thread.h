// Catalyst is a UCI compliant chess engine
// Copyright (C) 2026 Anany Tanwar

// Catalyst is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// Catalyst is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#pragma once

#include "board.h"
#include "search.h"
#include "timeman.h"
#include "types.h"

#include <atomic>
#include <condition_variable>
#include <memory>
#include <mutex>
#include <thread>
#include <vector>

namespace Catalyst {

class ThreadPool {
public:
    std::atomic<bool> stop { false };

    explicit ThreadPool(int numThreads = 1);
    ~ThreadPool();

    void set_threads(int n);

    Move search(Board &board, TimeManager &tm);

    void stop_search();

    void wait_for_idle();

    void clear_all();

    uint64_t total_nodes() const;

    Move ponder_move() const;

    int thread_count() const { return static_cast<int>(workers_.size()); }

    Search &main_search() { return *workers_[0]->searcher; }

private:
    struct Worker {
        std::unique_ptr<Search> searcher;
        std::unique_ptr<Board>  board;

        std::mutex              mutex;
        std::condition_variable cv;

        bool searching = false;
        bool exiting   = false;

        std::unique_ptr<std::thread> thread;
    };

    std::vector<std::unique_ptr<Worker>> workers_;

    std::atomic<uint64_t> sharedNodes_ { 0 };

    Board       *rootBoard_ = nullptr;
    TimeManager *rootTm_    = nullptr;

    std::mutex              mainMutex_;
    std::condition_variable mainCv_;

    void spawn_worker(int idx);
    void idle_loop(int idx);

    const Search *best_thread() const;
};

}