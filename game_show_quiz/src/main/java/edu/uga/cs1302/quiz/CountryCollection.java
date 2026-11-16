package edu.uga.cs1302.quiz;

import java.io.FileReader;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.io.Reader;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;

import org.apache.commons.csv.CSVFormat;
import org.apache.commons.csv.CSVRecord;

/** Loads and provides the country/continent dataset for quiz questions. */
public class CountryCollection {
    private final List<Country> countries;

    public CountryCollection() {
        this.countries = new ArrayList<>();
    }

    /**
     * Backwards-compatible entry point for an external CSV path.
     * Retained for the original command-line test harness.
     */
    public void readFromCSV(String filepath) throws IOException {
        try (Reader reader = new FileReader(filepath)) {
            loadRecords(reader);
        }
    }

    /**
     * Load the dataset from the Maven classpath, independent of the user's home directory.
     * For the shipped file, use "country_continent.csv".
     */
    public void readFromResource(String resourceName) throws IOException {
        String path = resourceName.startsWith("/") ? resourceName : "/" + resourceName;
        try (InputStream stream = CountryCollection.class.getResourceAsStream(path)) {
            if (stream == null) {
                throw new IOException("Classpath CSV resource not found: " + path);
            }
            try (Reader reader = new InputStreamReader(stream, StandardCharsets.UTF_8)) {
                loadRecords(reader);
            }
        }
    }

    private void loadRecords(Reader reader) throws IOException {
        Iterable<CSVRecord> records = CSVFormat.DEFAULT.parse(reader);
        for (CSVRecord record : records) {
            String name = record.get(0);
            String continent = record.get(1);
            countries.add(new Country(name, continent));
        }
    }

    public Country getCountry(int index) {
        return countries.get(index);
    }

    public int size() {
        return countries.size();
    }

    @Override
    public String toString() {
        StringBuilder sb = new StringBuilder();
        for (Country country : countries) {
            sb.append(country.toString()).append("\n");
        }
        return sb.toString();
    }
}
