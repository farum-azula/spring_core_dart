package dev.farumazula.datareference;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Map;

import org.springframework.boot.ApplicationArguments;
import org.springframework.boot.ApplicationRunner;
import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.stereotype.Component;

/**
 * The Spring side of the data verification: runs the scenarios of
 * {@link Scenarios} on the PostgreSQL database it is given and writes their
 * outcomes as JSON.
 *
 * <pre>
 * java -jar data-reference-0.0.0.jar \
 *   --spring.datasource.url=jdbc:postgresql://localhost:5432/matrix \
 *   --spring.datasource.username=postgres --spring.datasource.password=test \
 *   --out=outcomes.json [--only=isolation/]
 * </pre>
 */
@SpringBootApplication
public class DataReferenceApplication {
    public static void main(String[] args) {
        // PostgreSQL refuses some of the JVM's zone aliases (Europe/Kiev).
        java.util.TimeZone.setDefault(java.util.TimeZone.getTimeZone("UTC"));
        ConfigurableApplicationContext context = SpringApplication.run(DataReferenceApplication.class, args);
        System.exit(SpringApplication.exit(context));
    }

    @Component
    static class Runner implements ApplicationRunner {
        private final Scenarios scenarios;

        Runner(Scenarios scenarios) {
            this.scenarios = scenarios;
        }

        @Override
        public void run(ApplicationArguments args) throws Exception {
            String only = args.containsOption("only") ? args.getOptionValues("only").get(0) : "";
            Map<String, Object> outcomes = scenarios.runAll(only);
            String json = Json.write(outcomes);
            if (args.containsOption("out")) {
                Files.writeString(Path.of(args.getOptionValues("out").get(0)), json);
            } else {
                System.out.println(json);
            }
        }
    }
}
