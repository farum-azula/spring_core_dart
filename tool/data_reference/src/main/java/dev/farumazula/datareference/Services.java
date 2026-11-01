package dev.farumazula.datareference;

import java.util.LinkedHashMap;
import java.util.Map;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

/**
 * The two services of the propagation matrix, with real {@code @Transactional}
 * annotations: {@code Outer} calls {@code Inner}, whose method has the
 * propagation under test. The Dart suite has the same two services.
 */
final class Services {
    private Services() {}

    static final String[] INNERS = {
        "required", "supports", "mandatory", "requiresNew", "notSupported", "never", "nested",
    };

    /** What the inner method does after writing its row. */
    enum Variant {
        ok, innerThrowsCaught, innerThrowsPropagates, outerThrowsAfter
    }

    /** The state one scenario shares between its services. */
    static final class Ctx {
        final Env env;
        final Variant variant;
        final String innerPropagation;
        final Map<String, Object> out = new LinkedHashMap<>();
        String outerXid = "none";
        /** What the inner method does instead of its usual work, when set. */
        Runnable work;

        Ctx(Env env, Variant variant, String innerPropagation) {
            this.env = env;
            this.variant = variant;
            this.innerPropagation = innerPropagation;
        }

        boolean innerThrows() {
            return variant == Variant.innerThrowsCaught || variant == Variant.innerThrowsPropagates;
        }

        void innerWork() {
            if (work != null) {
                work.run();
                return;
            }
            out.put("innerSeesO1", env.scalar("select count(*) from log where who = 'o1'"));
            String state = env.txState();
            out.put("innerTx", state.equals("none") ? "none" : (state.equals(outerXid) ? "same" : "new"));
            env.jdbc.update("insert into log (who) values ('i')");
            if (innerThrows()) {
                throw new Exceptions.Boom();
            }
        }
    }

    @Service
    public static class Inner {
        @Transactional(propagation = Propagation.REQUIRED)
        public void required(Ctx c) { c.innerWork(); }

        @Transactional(propagation = Propagation.SUPPORTS)
        public void supports(Ctx c) { c.innerWork(); }

        @Transactional(propagation = Propagation.MANDATORY)
        public void mandatory(Ctx c) { c.innerWork(); }

        @Transactional(propagation = Propagation.REQUIRES_NEW)
        public void requiresNew(Ctx c) { c.innerWork(); }

        @Transactional(propagation = Propagation.NOT_SUPPORTED)
        public void notSupported(Ctx c) { c.innerWork(); }

        @Transactional(propagation = Propagation.NEVER)
        public void never(Ctx c) { c.innerWork(); }

        @Transactional(propagation = Propagation.NESTED)
        public void nested(Ctx c) { c.innerWork(); }
    }

    @Service
    public static class Outer {
        private final Env env;
        private final Inner inner;

        Outer(Env env, Inner inner) {
            this.env = env;
            this.inner = inner;
        }

        private void callInner(Ctx c) {
            switch (c.innerPropagation) {
                case "required" -> inner.required(c);
                case "supports" -> inner.supports(c);
                case "mandatory" -> inner.mandatory(c);
                case "requiresNew" -> inner.requiresNew(c);
                case "notSupported" -> inner.notSupported(c);
                case "never" -> inner.never(c);
                case "nested" -> inner.nested(c);
                default -> throw new IllegalArgumentException(c.innerPropagation);
            }
        }

        private void body(Ctx c) {
            env.jdbc.update("insert into log (who) values ('o1')");
            c.outerXid = env.txState();
            c.out.put("outerTx", c.outerXid.equals("none") ? "none" : "tx");
            try {
                callInner(c);
                c.out.put("inner", "ok");
            } catch (RuntimeException | Error error) {
                if (c.variant == Variant.innerThrowsPropagates) {
                    throw error;
                }
                c.out.put("inner", Env.kindOf(error));
            }
            c.out.put("outerSeesI", env.scalar("select count(*) from log where who = 'i'"));
            env.jdbc.update("insert into log (who) values ('o2')");
            if (c.variant == Variant.outerThrowsAfter) {
                throw new Exceptions.Boom();
            }
        }

        /** A method with no annotation. */
        public void none(Ctx c) { body(c); }

        @Transactional(propagation = Propagation.REQUIRED)
        public void required(Ctx c) { body(c); }

        @Transactional(propagation = Propagation.SUPPORTS)
        public void supports(Ctx c) { body(c); }

        @Transactional(propagation = Propagation.MANDATORY)
        public void mandatory(Ctx c) { body(c); }

        @Transactional(propagation = Propagation.REQUIRES_NEW)
        public void requiresNew(Ctx c) { body(c); }

        @Transactional(propagation = Propagation.NOT_SUPPORTED)
        public void notSupported(Ctx c) { body(c); }

        @Transactional(propagation = Propagation.NEVER)
        public void never(Ctx c) { body(c); }

        @Transactional(propagation = Propagation.NESTED)
        public void nested(Ctx c) { body(c); }
    }
}
