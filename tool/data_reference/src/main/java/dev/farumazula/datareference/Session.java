package dev.farumazula.datareference;

import java.util.concurrent.BlockingQueue;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.LinkedBlockingQueue;

import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

/**
 * One transaction driven step by step: {@link #begin} starts it on a thread
 * of its own, {@link #run} runs an action in it (the action's value, or its
 * error as {@code !Kind}), {@link #end} commits or rolls it back and gives
 * the outcome of that ({@code ok}, or the error of the commit). The actions
 * of one session run in order; two sessions run side by side.
 */
final class Session {
    private record Command(Runnable run, boolean end, boolean commit) {}

    private final BlockingQueue<Command> queue = new LinkedBlockingQueue<>();
    private final CompletableFuture<Object> done = new CompletableFuture<>();

    private Session() {}

    static Session begin(Env env, TransactionDefinition definition) {
        Session session = new Session();
        CountDownLatch started = new CountDownLatch(1);
        Thread thread = new Thread(() -> {
            try {
                new TransactionTemplate(env.manager, definition).executeWithoutResult(status -> {
                    started.countDown();
                    try {
                        while (true) {
                            Command command = session.queue.take();
                            if (command.end()) {
                                if (!command.commit()) {
                                    status.setRollbackOnly();
                                }
                                return;
                            }
                            command.run().run();
                        }
                    } catch (InterruptedException e) {
                        throw new IllegalStateException(e);
                    }
                });
                session.done.complete("ok");
            } catch (Throwable error) {
                started.countDown();
                session.done.complete("!" + Env.kindOf(error));
            }
        });
        thread.setDaemon(true);
        thread.start();
        try {
            started.await();
        } catch (InterruptedException e) {
            throw new IllegalStateException(e);
        }
        return session;
    }

    static Session begin(Env env) {
        return begin(env, new org.springframework.transaction.support.DefaultTransactionDefinition());
    }

    /**
     * Runs the action in the transaction; completes with its value or
     * {@code !Kind}. Not waiting for it lets another session act while it
     * waits for a lock.
     */
    CompletableFuture<Object> run(Env.Action action) {
        CompletableFuture<Object> result = new CompletableFuture<>();
        queue.add(new Command(() -> result.complete(Env.attempt(action)), false, true));
        return result;
    }

    /** Commits (or rolls back) and gives {@code ok} or the error of the end. */
    CompletableFuture<Object> end(boolean commit) {
        queue.add(new Command(() -> {}, true, commit));
        return done;
    }

    CompletableFuture<Object> end() {
        return end(true);
    }
}
