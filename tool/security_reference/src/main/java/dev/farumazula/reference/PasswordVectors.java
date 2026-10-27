package dev.farumazula.reference;

import java.nio.file.Files;
import java.nio.file.Path;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import tools.jackson.databind.ObjectMapper;
import org.springframework.security.crypto.argon2.Argon2PasswordEncoder;
import org.springframework.security.crypto.factory.PasswordEncoderFactories;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.crypto.password.Pbkdf2PasswordEncoder;
import org.springframework.security.crypto.scrypt.SCryptPasswordEncoder;

/**
 * Password hashes in both directions:
 *
 * <pre>
 * write &lt;file&gt;           hashes made by Spring Security's encoders
 * check &lt;file&gt;           checks hashes made by the Dart encoders
 * </pre>
 *
 * A file is a JSON list of {"id", "password", "hash"}.
 */
public final class PasswordVectors {

  public static void main(String[] args) throws Exception {
    var mapper = new ObjectMapper();
    var encoders = encoders();
    switch (args[0]) {
      case "write" -> {
        var out = new java.util.ArrayList<Map<String, String>>();
        for (var password : List.of("password", "", "pässwörd ✓", "a:b\\c\"d")) {
          for (var entry : encoders.entrySet()) {
            var vector = new LinkedHashMap<String, String>();
            vector.put("id", entry.getKey());
            vector.put("password", password);
            vector.put("hash", entry.getValue().encode(password));
            out.add(vector);
          }
        }
        mapper.writerWithDefaultPrettyPrinter().writeValue(Path.of(args[1]).toFile(), out);
      }
      case "check" -> {
        List<Map<String, String>> vectors = mapper.readValue(
            Files.readString(Path.of(args[1])),
            mapper.getTypeFactory().constructCollectionType(List.class, Map.class));
        var failures = 0;
        for (var vector : vectors) {
          var encoder = encoders.get(vector.get("id"));
          var password = vector.get("password");
          // An empty password never matches (Spring Security 7).
          var ok = password.isEmpty()
              ? !encoder.matches(password, vector.get("hash"))
              : encoder.matches(password, vector.get("hash"))
                  && !encoder.matches(password + "x", vector.get("hash"));
          System.out.println((ok ? "ok    " : "FAIL  ") + vector.get("id") + " " + vector.get("hash"));
          if (!ok) failures++;
        }
        System.exit(failures == 0 ? 0 : 1);
      }
      default -> throw new IllegalArgumentException(args[0]);
    }
  }

  static Map<String, PasswordEncoder> encoders() {
    var encoders = new LinkedHashMap<String, PasswordEncoder>();
    encoders.put("argon2", Argon2PasswordEncoder.defaultsForSpringSecurity_v5_8());
    encoders.put("pbkdf2", Pbkdf2PasswordEncoder.defaultsForSpringSecurity_v5_8());
    encoders.put("scrypt", SCryptPasswordEncoder.defaultsForSpringSecurity_v5_8());
    encoders.put("delegating", PasswordEncoderFactories.createDelegatingPasswordEncoder());
    return encoders;
  }
}
