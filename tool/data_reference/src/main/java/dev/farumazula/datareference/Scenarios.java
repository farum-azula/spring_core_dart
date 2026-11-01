package dev.farumazula.datareference;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.Callable;
import java.util.concurrent.CompletableFuture;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Component;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.DefaultTransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

import dev.farumazula.datareference.Exceptions.Boom;
import dev.farumazula.datareference.Exceptions.Checked;
import dev.farumazula.datareference.Exceptions.Fatal;
import dev.farumazula.datareference.Exceptions.Hard;
import dev.farumazula.datareference.Exceptions.Soft;
import dev.farumazula.datareference.Services.Ctx;
import dev.farumazula.datareference.Services.Inner;
import dev.farumazula.datareference.Services.Outer;

/**
 * The scenarios of the transaction matrix. Each one resets the tables,
 * drives its transactions and returns a normalized outcome; the Dart suite
 * (spring_boot_starter_data/test/transaction_matrix/scenarios.dart) has the
 * same scenarios with the same ids and keys, and the differential test
 * compares outcome by outcome.
 *
 * <p>Groups: {@code propagation/<outer>/<inner>/<variant>} (every outer, and
 * none, against every inner), {@code propagation-lock/<inner>},
 * {@code rules/*}, {@code template/*}, {@code readonly/*},
 * {@code isolation/<anomaly>/<level>}, {@code lock/*}, {@code version/*},
 * {@code timeout/*}.
 */
@Component
public class Scenarios {
    private static final String[] OUTERS = {
        "none", "required", "supports", "mandatory", "requiresNew", "notSupported", "never", "nested",
    };

    private static final String[] LEVELS = {
        "default", "readUncommitted", "readCommitted", "repeatableRead", "serializable",
    };

    private final Env env;
    private final Outer outer;
    private final Inner inner;
    private final Methods methods;
    private final StockRepository stocks;
    private final AccountRepository accounts;
    private final Map<String, Callable<Map<String, Object>>> all = new LinkedHashMap<>();

    Scenarios(Env env, Outer outer, Inner inner, Methods methods, StockRepository stocks,
              AccountRepository accounts) {
        this.env = env;
        this.outer = outer;
        this.inner = inner;
        this.methods = methods;
        this.stocks = stocks;
        this.accounts = accounts;
        propagation();
        propagationLocks();
        rules();
        templates();
        readOnly();
        isolation();
        locks();
        versions();
        timeouts();
    }

    /** Runs the scenarios whose id starts with {@code only}. */
    Map<String, Object> runAll(String only) throws Exception {
        env.createSchema();
        Map<String, Object> outcomes = new LinkedHashMap<>();
        ExecutorService executor = Executors.newCachedThreadPool(r -> {
            Thread thread = new Thread(r);
            thread.setDaemon(true);
            return thread;
        });
        for (Map.Entry<String, Callable<Map<String, Object>>> entry : all.entrySet()) {
            if (!entry.getKey().startsWith(only)) {
                continue;
            }
            long start = System.nanoTime();
            env.reset();
            CompletableFuture<Map<String, Object>> run = new CompletableFuture<>();
            executor.submit(() -> {
                try {
                    run.complete(entry.getValue().call());
                } catch (Throwable error) {
                    run.completeExceptionally(error);
                }
            });
            try {
                outcomes.put(entry.getKey(), run.get(60, TimeUnit.SECONDS));
            } catch (TimeoutException e) {
                outcomes.put(entry.getKey(), Map.of("TIMEOUT", true));
            }
            System.err.println(entry.getKey() + " " + (System.nanoTime() - start) / 1_000_000 + "ms");
        }
        return outcomes;
    }

    private void add(String id, Callable<Map<String, Object>> scenario) {
        if (all.put(id, scenario) != null) {
            throw new IllegalStateException("Two scenarios named " + id);
        }
    }

    private static Map<String, Object> map() {
        return new LinkedHashMap<>();
    }

    // ---------------------------------------------------------- propagation

    private void callOuter(String propagation, Ctx c) {
        switch (propagation) {
            case "none" -> outer.none(c);
            case "required" -> outer.required(c);
            case "supports" -> outer.supports(c);
            case "mandatory" -> outer.mandatory(c);
            case "requiresNew" -> outer.requiresNew(c);
            case "notSupported" -> outer.notSupported(c);
            case "never" -> outer.never(c);
            case "nested" -> outer.nested(c);
            default -> throw new IllegalArgumentException(propagation);
        }
    }

    private void propagation() {
        for (String outerName : OUTERS) {
            for (String innerName : Services.INNERS) {
                for (Services.Variant variant : Services.Variant.values()) {
                    add("propagation/" + outerName + "/" + innerName + "/" + variant.name(), () -> {
                        Ctx c = new Ctx(env, variant, innerName);
                        try {
                            callOuter(outerName, c);
                            c.out.put("outer", "ok");
                        } catch (Throwable error) {
                            c.out.put("outer", Env.kindOf(error));
                        }
                        c.out.put("rows", env.logRows());
                        return c.out;
                    });
                }
            }
        }
    }

    private void callInner(String propagation, Ctx c) {
        switch (propagation) {
            case "required" -> inner.required(c);
            case "supports" -> inner.supports(c);
            case "mandatory" -> inner.mandatory(c);
            case "requiresNew" -> inner.requiresNew(c);
            case "notSupported" -> inner.notSupported(c);
            case "never" -> inner.never(c);
            case "nested" -> inner.nested(c);
            default -> throw new IllegalArgumentException(propagation);
        }
    }

    // What an inner method waits for when the outer one holds the row: each
    // statement stops after a second.
    private void propagationLocks() {
        for (String innerName : Services.INNERS) {
            add("propagation-lock/" + innerName, () -> {
                JdbcTemplate timed = env.jdbcWithTimeout(1);
                Map<String, Object> out = map();
                try {
                    methods.plain(() -> {
                        env.jdbc.update("update wallets set balance = balance + 1 where id = 1");
                        Ctx c = new Ctx(env, Services.Variant.ok, innerName);
                        c.work = () -> timed.update("update wallets set balance = balance + 1 where id = 1");
                        try {
                            callInner(innerName, c);
                            out.put("inner", "ok");
                        } catch (Throwable error) {
                            out.put("inner", Env.kindOf(error));
                        }
                    });
                    out.put("outer", "ok");
                } catch (Throwable error) {
                    out.put("outer", Env.kindOf(error));
                }
                out.put("balance", env.scalar("select balance from wallets where id = 1"));
                return out;
            });
        }
    }

    // ---------------------------------------------------------------- rules

    @FunctionalInterface
    private interface Method {
        void call(Env.Body body) throws Throwable;
    }

    private void rule(String id, Method method, Callable<Throwable> throwing) {
        add("rules/" + id, () -> {
            Map<String, Object> out = map();
            try {
                method.call(() -> {
                    env.jdbc.update("insert into log (who) values ('o1')");
                    throw throwing.call();
                });
                out.put("outer", "ok");
            } catch (Throwable error) {
                out.put("outer", Env.kindOf(error));
            }
            out.put("rows", env.logRows());
            return out;
        });
    }

    private void rules() {
        rule("default-rollback", methods::plain, Boom::new);
        rule("noRollbackFor-commits", methods::noRollbackForSoft, Soft::new);
        rule("noRollbackFor-covers-subclass", methods::noRollbackForSoft, Hard::new);
        rule("rollbackFor-beats-noRollbackFor-of-supertype", methods::noRollbackForSoftRollbackForHard, Hard::new);
        rule("noRollbackFor-closer-than-rollbackFor", methods::rollbackForSoftNoRollbackForHard, Hard::new);
        rule("unlisted-rolls-back", methods::noRollbackForSoft, Boom::new);
        rule("checked-exception", methods::plain, Checked::new);
        rule("rollbackFor-checked", methods::rollbackForChecked, Checked::new);
        rule("error-rolls-back", methods::plain, Fatal::new);
        add("rules/joined-noRollbackFor", () -> {
            Map<String, Object> out = map();
            try {
                methods.plain(() -> {
                    env.jdbc.update("insert into log (who) values ('o1')");
                    try {
                        methods.noRollbackForSoft(() -> {
                            env.jdbc.update("insert into log (who) values ('i')");
                            throw new Soft();
                        });
                    } catch (Throwable error) {
                        out.put("inner", Env.kindOf(error));
                    }
                    env.jdbc.update("insert into log (who) values ('o2')");
                });
                out.put("outer", "ok");
            } catch (Throwable error) {
                out.put("outer", Env.kindOf(error));
            }
            out.put("rows", env.logRows());
            return out;
        });
    }

    // ------------------------------------------------------------ templates

    private TransactionTemplate template() {
        return new TransactionTemplate(env.manager);
    }

    private void templates() {
        add("template/commit", () -> {
            Map<String, Object> out = map();
            out.put("result", template().execute(status -> {
                env.jdbc.update("insert into log (who) values ('o1')");
                return "value";
            }));
            out.put("rows", env.logRows());
            return out;
        });
        add("template/exception", () -> {
            Map<String, Object> out = map();
            out.put("outer", Env.attempt(() -> template().execute(status -> {
                env.jdbc.update("insert into log (who) values ('o1')");
                throw new Boom();
            })));
            out.put("rows", env.logRows());
            return out;
        });
        add("template/set-rollback-only", () -> {
            Map<String, Object> out = map();
            out.put("outer", Env.attempt(() -> template().execute(status -> {
                env.jdbc.update("insert into log (who) values ('o1')");
                status.setRollbackOnly();
                return "value";
            })));
            out.put("rows", env.logRows());
            return out;
        });
        add("template/set-rollback-only-joined", () -> {
            Map<String, Object> out = map();
            out.put("outer", Env.attempt(() -> template().execute(status -> {
                env.jdbc.update("insert into log (who) values ('o1')");
                out.put("inner", Env.attempt(() -> template().execute(innerStatus -> {
                    env.jdbc.update("insert into log (who) values ('i')");
                    innerStatus.setRollbackOnly();
                    return "value";
                })));
                return null;
            })));
            out.put("rows", env.logRows());
            return out;
        });
    }

    // ------------------------------------------------------------ read only

    /** Runs {@code work} in {@code method}'s transaction and returns its result. */
    private static Object through(Method method, Callable<?> work) throws Throwable {
        Object[] result = new Object[1];
        method.call(() -> result[0] = work.call());
        return result[0];
    }

    private void readOnlyOp(String id, String sql, boolean query) {
        add("readonly/" + id, () -> {
            Map<String, Object> out = map();
            out.put("outer", Env.completion(() -> out.put("op", through(methods::readOnly,
                    () -> Env.attempt(() -> query ? (Object) env.scalar(sql) : (Object) env.jdbc.update(sql))))));
            out.put("rows", env.logRows());
            return out;
        });
    }

    private void readOnlyInner(String id, Method outerMethod, Method innerMethod) {
        add("readonly/" + id, () -> {
            Map<String, Object> out = map();
            out.put("outer", Env.completion(() -> through(outerMethod, () -> {
                out.put("inner", Env.attempt(() -> through(innerMethod,
                        () -> env.jdbc.update("insert into log (who) values ('i')"))));
                return null;
            })));
            out.put("rows", env.logRows());
            return out;
        });
    }

    private void readOnly() {
        readOnlyOp("read-ok", "select count(*) from wallets", true);
        readOnlyOp("insert-refused", "insert into log (who) values ('o1')", false);
        readOnlyOp("update-refused", "update wallets set balance = 0", false);
        readOnlyOp("delete-refused", "delete from wallets", false);
        readOnlyOp("select-for-update-refused",
                "select count(*) from (select id from wallets for update) w", true);
        readOnlyInner("joined-read-write-keeps-write", methods::plain, methods::readOnly);
        readOnlyInner("requires-new-read-only-in-read-write", methods::plain, methods::requiresNewReadOnly);
        readOnlyInner("joined-read-write-in-read-only", methods::readOnly, methods::plain);
    }

    // ------------------------------------------------------------ isolation

    private static TransactionDefinition at(String level) {
        DefaultTransactionDefinition definition = new DefaultTransactionDefinition();
        definition.setIsolationLevel(switch (level) {
            case "default" -> TransactionDefinition.ISOLATION_DEFAULT;
            case "readUncommitted" -> TransactionDefinition.ISOLATION_READ_UNCOMMITTED;
            case "readCommitted" -> TransactionDefinition.ISOLATION_READ_COMMITTED;
            case "repeatableRead" -> TransactionDefinition.ISOLATION_REPEATABLE_READ;
            case "serializable" -> TransactionDefinition.ISOLATION_SERIALIZABLE;
            default -> throw new IllegalArgumentException(level);
        });
        return definition;
    }

    private Object balance() {
        return env.scalar("select balance from wallets where id = 1");
    }

    private Object isolationLevel() {
        return env.text("show transaction_isolation");
    }

    private Object write(Session session, boolean atomic, Object read, int by) {
        long base = ((Number) read).longValue();
        return session.run(() -> atomic
                ? env.jdbc.update("update wallets set balance = balance + " + by + " where id = 1")
                : env.jdbc.update("update wallets set balance = " + (base + by) + " where id = 1")).join();
    }

    private void isolation() {
        for (String level : LEVELS) {
            TransactionDefinition definition = at(level);
            add("isolation/dirty-read/" + level, () -> {
                Map<String, Object> out = map();
                Session a = Session.begin(env, definition);
                Session b = Session.begin(env, definition);
                a.run(() -> env.jdbc.update("update wallets set balance = 0 where id = 1")).join();
                out.put("bRead", b.run(this::balance).join());
                out.put("level", b.run(this::isolationLevel).join());
                a.end(false).join();
                b.end().join();
                return out;
            });
            add("isolation/non-repeatable-read/" + level, () -> {
                Map<String, Object> out = map();
                Session a = Session.begin(env, definition);
                Session b = Session.begin(env);
                out.put("firstRead", a.run(this::balance).join());
                out.put("level", a.run(this::isolationLevel).join());
                b.run(() -> env.jdbc.update("update wallets set balance = 150 where id = 1")).join();
                out.put("bEnd", b.end().join());
                out.put("secondRead", a.run(this::balance).join());
                out.put("aEnd", a.end().join());
                return out;
            });
            add("isolation/phantom/" + level, () -> {
                String count = "select count(*) from wallets where balance >= 100";
                Map<String, Object> out = map();
                Session a = Session.begin(env, definition);
                Session b = Session.begin(env);
                out.put("firstCount", a.run(() -> env.scalar(count)).join());
                out.put("level", a.run(this::isolationLevel).join());
                b.run(() -> env.jdbc.update("insert into wallets values (3, 'cy', 200)")).join();
                out.put("bEnd", b.end().join());
                out.put("secondCount", a.run(() -> env.scalar(count)).join());
                out.put("aEnd", a.end().join());
                return out;
            });
            for (boolean atomic : new boolean[] {false, true}) {
                add("isolation/lost-update-" + (atomic ? "atomic" : "read-modify-write") + "/" + level, () -> {
                    Map<String, Object> out = map();
                    Session a = Session.begin(env, definition);
                    Session b = Session.begin(env, definition);
                    Object aRead = a.run(this::balance).join();
                    Object bRead = b.run(this::balance).join();
                    out.put("level", a.run(this::isolationLevel).join());
                    out.put("aUpdate", write(a, atomic, aRead, 10));
                    long bBase = ((Number) bRead).longValue();
                    CompletableFuture<Object> bUpdate = b.run(() -> atomic
                            ? env.jdbc.update("update wallets set balance = balance + 20 where id = 1")
                            : env.jdbc.update("update wallets set balance = " + (bBase + 20) + " where id = 1"));
                    out.put("bBlocked", env.awaitBlocked());
                    out.put("aEnd", a.end().join());
                    out.put("bUpdate", bUpdate.join());
                    out.put("bEnd", b.end().join());
                    out.put("balance", balance());
                    return out;
                });
            }
            add("isolation/write-skew/" + level, () -> {
                String count = "select count(*) from doctors where on_call";
                Map<String, Object> out = map();
                Session a = Session.begin(env, definition);
                Session b = Session.begin(env, definition);
                out.put("aCount", a.run(() -> env.scalar(count)).join());
                out.put("bCount", b.run(() -> env.scalar(count)).join());
                out.put("level", a.run(this::isolationLevel).join());
                out.put("aUpdate", a.run(() -> env.jdbc.update(
                        "update doctors set on_call = false where name = 'alice'")).join());
                out.put("bUpdate", b.run(() -> env.jdbc.update(
                        "update doctors set on_call = false where name = 'bob'")).join());
                out.put("aEnd", a.end().join());
                out.put("bEnd", b.end().join());
                out.put("onCall", env.scalar(count));
                return out;
            });
        }
        add("isolation/deadlock", () -> {
            Map<String, Object> out = map();
            Session a = Session.begin(env);
            Session b = Session.begin(env);
            a.run(() -> env.jdbc.update("update wallets set balance = 1 where id = 1")).join();
            b.run(() -> env.jdbc.update("update wallets set balance = 2 where id = 2")).join();
            CompletableFuture<Object> aWaits = a.run(() -> env.jdbc.update("update wallets set balance = 3 where id = 2"));
            out.put("aBlocked", env.awaitBlocked());
            CompletableFuture<Object> bWaits = b.run(() -> env.jdbc.update("update wallets set balance = 4 where id = 1"));
            // The victim fails after the deadlock timeout; the other one goes
            // on when the victim's transaction ends.
            Object first = CompletableFuture.anyOf(aWaits, bWaits).join();
            boolean aIsVictim = aWaits.isDone() && first == aWaits.join();
            Session victim = aIsVictim ? a : b;
            Session survivor = aIsVictim ? b : a;
            Object victimResult = aIsVictim ? aWaits.join() : bWaits.join();
            Object victimEnd = victim.end().join();
            Object survivorResult = (aIsVictim ? bWaits : aWaits).join();
            Object survivorEnd = survivor.end().join();
            out.put("updates", sorted(victimResult, survivorResult));
            out.put("ends", sorted(victimEnd, survivorEnd));
            return out;
        });
    }

    private static List<String> sorted(Object... values) {
        List<String> list = new ArrayList<>();
        for (Object value : values) {
            list.add(String.valueOf(value));
        }
        list.sort(null);
        return list;
    }

    // ---------------------------------------------------------------- locks

    private Object lockStock(String sku) {
        return stocks.findBySku(sku).map(Stock::quantity).orElse(null);
    }

    private Object skus(String suffix) {
        return env.jdbc.queryForList("select sku from stock order by sku" + suffix, String.class);
    }

    private Object shareSkus() {
        List<String> skus = new ArrayList<>();
        for (Stock stock : stocks.findByQuantityLessThan(2)) {
            skus.add(stock.sku());
        }
        return skus;
    }

    private void locks() {
        for (boolean commit : new boolean[] {true, false}) {
            add("lock/for-update-waits-and-sees-the-" + (commit ? "update" : "rollback"), () -> {
                Map<String, Object> out = map();
                Session a = Session.begin(env);
                Session b = Session.begin(env);
                a.run(() -> lockStock("a")).join();
                a.run(() -> env.jdbc.update("update stock set quantity = 6 where sku = 'a'")).join();
                CompletableFuture<Object> bLock = b.run(() -> lockStock("a"));
                out.put("bBlocked", env.awaitBlocked());
                out.put("aEnd", a.end(commit).join());
                out.put("bQuantity", bLock.join());
                out.put("bEnd", b.end().join());
                return out;
            });
        }
        add("lock/for-share-is-shared-but-not-with-a-writer", () -> {
            Map<String, Object> out = map();
            Session a = Session.begin(env);
            Session b = Session.begin(env);
            out.put("aShare", a.run(this::shareSkus).join());
            out.put("bShare", b.run(this::shareSkus).join());
            out.put("bUpdateLock", b.run(() -> skus(" for update nowait")).join());
            out.put("aEnd", a.end().join());
            out.put("bEnd", b.end().join());
            return out;
        });
        add("lock/for-share-blocks-a-writer", () -> {
            Map<String, Object> out = map();
            Session a = Session.begin(env);
            Session b = Session.begin(env);
            a.run(this::shareSkus).join();
            CompletableFuture<Object> bUpdate = b.run(
                    () -> env.jdbc.update("update stock set quantity = quantity + 1 where sku = 'b'"));
            out.put("bBlocked", env.awaitBlocked());
            out.put("aEnd", a.end().join());
            out.put("bUpdate", bUpdate.join());
            out.put("bEnd", b.end().join());
            out.put("quantity", env.scalar("select quantity from stock where sku = 'b'"));
            return out;
        });
        add("lock/nowait", () -> {
            Map<String, Object> out = map();
            Session a = Session.begin(env);
            Session b = Session.begin(env);
            a.run(() -> lockStock("a")).join();
            long start = System.nanoTime();
            out.put("bLock", b.run(() -> skus(" for update nowait")).join());
            out.put("failedAtOnce", System.nanoTime() - start < 1_000_000_000L);
            out.put("aEnd", a.end().join());
            out.put("bEnd", b.end().join());
            return out;
        });
        add("lock/skip-locked", () -> {
            Map<String, Object> out = map();
            Session a = Session.begin(env);
            Session b = Session.begin(env);
            a.run(() -> lockStock("a")).join();
            out.put("bSkus", b.run(() -> skus(" for update skip locked")).join());
            out.put("aEnd", a.end().join());
            out.put("bEnd", b.end().join());
            return out;
        });
        add("lock/skip-locked-with-limit", () -> {
            Map<String, Object> out = map();
            Session a = Session.begin(env);
            Session b = Session.begin(env);
            a.run(() -> lockStock("a")).join();
            out.put("bSkus", b.run(() -> skus(" limit 1 for update skip locked")).join());
            out.put("aEnd", a.end().join());
            out.put("bEnd", b.end().join());
            return out;
        });
        add("lock/lock-timeout", () -> {
            Map<String, Object> out = map();
            Session a = Session.begin(env);
            Session b = Session.begin(env);
            a.run(() -> lockStock("a")).join();
            long start = System.nanoTime();
            out.put("bLock", b.run(() -> {
                env.jdbc.execute("set local lock_timeout = '300ms'");
                return skus(" for update");
            }).join());
            out.put("waited", System.nanoTime() - start >= 250_000_000L);
            out.put("aEnd", a.end().join());
            out.put("bEnd", b.end().join());
            return out;
        });
        add("lock/plain-read-does-not-wait", () -> {
            Map<String, Object> out = map();
            Session a = Session.begin(env);
            Session b = Session.begin(env);
            a.run(() -> lockStock("a")).join();
            a.run(() -> env.jdbc.update("update stock set quantity = 6 where sku = 'a'")).join();
            out.put("bRead", b.run(() -> env.scalar("select quantity from stock where sku = 'a'")).join());
            out.put("aEnd", a.end().join());
            out.put("bEnd", b.end().join());
            return out;
        });
        add("lock/outside-a-transaction", () -> {
            Map<String, Object> out = map();
            out.put("result", Env.attempt(() -> lockStock("a")));
            return out;
        });
    }

    // ------------------------------------------------------------- versions

    private Account loadAccount() {
        return accounts.findById("acc-1").orElseThrow();
    }

    private Object saveAccount(Account loaded, String owner) {
        return accounts.save(new Account(loaded.iban(), owner, loaded.version())).version();
    }

    private Map<String, Object> accountRow(Map<String, Object> out) {
        out.put("owner", env.text("select owner from accounts where iban = 'acc-1'"));
        out.put("version", env.scalar("select version from accounts where iban = 'acc-1'"));
        return out;
    }

    private void versions() {
        add("version/lost-update-detected", () -> {
            Map<String, Object> out = map();
            Session a = Session.begin(env);
            Session b = Session.begin(env);
            Account aLoaded = (Account) a.run(this::loadAccount).join();
            Account bLoaded = (Account) b.run(this::loadAccount).join();
            out.put("aSave", a.run(() -> saveAccount(aLoaded, "a")).join());
            out.put("aEnd", a.end().join());
            out.put("bSave", b.run(() -> saveAccount(bLoaded, "b")).join());
            out.put("bEnd", b.end().join());
            return accountRow(out);
        });
        add("version/sequential-saves", () -> {
            Map<String, Object> out = map();
            out.put("first", Env.attempt(() -> template().execute(status -> saveAccount(loadAccount(), "a"))));
            out.put("second", Env.attempt(() -> template().execute(status -> saveAccount(loadAccount(), "b"))));
            return accountRow(out);
        });
        for (String level : new String[] {"readCommitted", "repeatableRead"}) {
            TransactionDefinition definition = at(level);
            add("version/concurrent-save-waits/" + level, () -> {
                Map<String, Object> out = map();
                Session a = Session.begin(env, definition);
                Session b = Session.begin(env, definition);
                Account aLoaded = (Account) a.run(this::loadAccount).join();
                Account bLoaded = (Account) b.run(this::loadAccount).join();
                out.put("aSave", a.run(() -> saveAccount(aLoaded, "a")).join());
                CompletableFuture<Object> bSave = b.run(() -> saveAccount(bLoaded, "b"));
                out.put("bBlocked", env.awaitBlocked());
                out.put("aEnd", a.end().join());
                out.put("bSave", bSave.join());
                out.put("bEnd", b.end().join());
                return accountRow(out);
            });
        }
    }

    // ------------------------------------------------------------- timeouts

    private static final String SLEEP = "select count(*) from pg_sleep(";

    private void timeouts() {
        add("timeout/statement-exceeds", () -> {
            Map<String, Object> out = map();
            out.put("outer", Env.completion(() -> methods.timeout1(() ->
                    out.put("statement", Env.attempt(() -> env.scalar(SLEEP + "3)"))))));
            return out;
        });
        add("timeout/lapsed-before-the-statement", () -> {
            Map<String, Object> out = map();
            out.put("outer", Env.completion(() -> methods.timeout1(() -> {
                Thread.sleep(1300);
                out.put("statement", Env.attempt(() -> env.scalar("select 1")));
            })));
            return out;
        });
        add("timeout/lock-wait-bounded", () -> {
            Map<String, Object> out = map();
            Session a = Session.begin(env);
            a.run(() -> env.jdbc.update("update wallets set balance = 1 where id = 1")).join();
            out.put("outer", Env.completion(() -> methods.timeout1(() ->
                    out.put("statement", Env.attempt(
                            () -> env.jdbc.update("update wallets set balance = 2 where id = 1"))))));
            out.put("aEnd", a.end().join());
            return out;
        });
        add("timeout/within-the-limit", () -> {
            Map<String, Object> out = map();
            out.put("outer", Env.completion(() -> methods.timeout5(() ->
                    out.put("statement", Env.attempt(() -> env.scalar(SLEEP + "0.2)"))))));
            return out;
        });
        add("timeout/ignored-when-joined", () -> {
            Map<String, Object> out = map();
            out.put("outer", Env.completion(() -> methods.plain(() ->
                    out.put("inner", Env.attempt(() -> through(methods::timeout1,
                            () -> env.scalar(SLEEP + "1.5)")))))));
            return out;
        });
        add("timeout/own-for-requires-new", () -> {
            Map<String, Object> out = map();
            out.put("outer", Env.completion(() -> methods.timeout10(() -> {
                out.put("inner", Env.attempt(() -> through(methods::requiresNewTimeout1,
                        () -> env.scalar(SLEEP + "3)"))));
                out.put("outerStatement", Env.attempt(() -> env.scalar("select 1")));
            })));
            return out;
        });
    }
}
