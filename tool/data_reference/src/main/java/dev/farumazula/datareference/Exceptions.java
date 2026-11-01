package dev.farumazula.datareference;

/** The exceptions of the scenarios (the Dart suite has the same names). */
final class Exceptions {
    private Exceptions() {}

    static class Boom extends RuntimeException {}

    /** The one transactions may commit through. */
    static class Soft extends RuntimeException {}

    static class Hard extends Soft {}

    /** Java's checked exception: Spring does not roll back on it by default. */
    static class Checked extends Exception {}

    static class Fatal extends Error {}
}
