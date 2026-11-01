package dev.farumazula.datareference;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Propagation;
import org.springframework.transaction.annotation.Transactional;

import dev.farumazula.datareference.Exceptions.Checked;
import dev.farumazula.datareference.Exceptions.Hard;
import dev.farumazula.datareference.Exceptions.Soft;

/**
 * Methods with the other {@code @Transactional} settings the scenarios use
 * (rollback rules, read only, timeouts); each runs the body it is given.
 */
@Service
public class Methods {
    @Transactional
    public void plain(Env.Body body) throws Throwable { body.run(); }

    @Transactional(noRollbackFor = Soft.class)
    public void noRollbackForSoft(Env.Body body) throws Throwable { body.run(); }

    @Transactional(noRollbackFor = Soft.class, rollbackFor = Hard.class)
    public void noRollbackForSoftRollbackForHard(Env.Body body) throws Throwable { body.run(); }

    @Transactional(rollbackFor = Soft.class, noRollbackFor = Hard.class)
    public void rollbackForSoftNoRollbackForHard(Env.Body body) throws Throwable { body.run(); }

    @Transactional(rollbackFor = Checked.class)
    public void rollbackForChecked(Env.Body body) throws Throwable { body.run(); }

    @Transactional(readOnly = true)
    public void readOnly(Env.Body body) throws Throwable { body.run(); }

    @Transactional(propagation = Propagation.REQUIRES_NEW, readOnly = true)
    public void requiresNewReadOnly(Env.Body body) throws Throwable { body.run(); }

    @Transactional(timeout = 1)
    public void timeout1(Env.Body body) throws Throwable { body.run(); }

    @Transactional(timeout = 5)
    public void timeout5(Env.Body body) throws Throwable { body.run(); }

    @Transactional(timeout = 10)
    public void timeout10(Env.Body body) throws Throwable { body.run(); }

    @Transactional(propagation = Propagation.REQUIRES_NEW, timeout = 1)
    public void requiresNewTimeout1(Env.Body body) throws Throwable { body.run(); }
}
