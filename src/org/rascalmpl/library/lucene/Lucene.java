package org.rascalmpl.library.lucene;

import java.io.File;
import java.io.IOException;

import org.apache.lucene.analysis.en.EnglishAnalyzer;
import org.apache.lucene.analysis.standard.StandardAnalyzer;
import org.apache.lucene.document.Document;
import org.apache.lucene.document.Field;
import org.apache.lucene.document.StringField;
import org.apache.lucene.document.TextField;
import org.apache.lucene.index.DirectoryReader;
import org.apache.lucene.index.IndexWriter;
import org.apache.lucene.index.IndexWriterConfig;
import org.apache.lucene.queryparser.classic.ParseException;
import org.apache.lucene.queryparser.classic.QueryParser;
import org.apache.lucene.search.IndexSearcher;
import org.apache.lucene.search.Query;
import org.apache.lucene.search.ScoreDoc;
import org.apache.lucene.search.TopDocs;
import org.apache.lucene.store.Directory;
import org.apache.lucene.store.FSDirectory;
import org.rascalmpl.interpreter.utils.RuntimeExceptionFactory;
import org.rascalmpl.value.IList;
import org.rascalmpl.value.IListWriter;
import org.rascalmpl.value.IMap;
import org.rascalmpl.value.ISourceLocation;
import org.rascalmpl.value.IString;
import org.rascalmpl.value.IValue;
import org.rascalmpl.value.IValueFactory;

/**
 * Rascal interface to the Lucene text search engine. Some sample code
 * was taken from the online tutorial at http://oak.cs.ucla.edu/cs144/projects/lucene/.
 * 
 * @author Mark Hills, East Carolina University
 *
 */
public class Lucene {

	private final IValueFactory values;
	private Directory indexDirectory = null;
	private IndexWriterConfig config = null;
	private IndexWriter indexWriter = null;
	private IndexSearcher searcher = null;
	private QueryParser parser = null;
	
	public Lucene(IValueFactory values) {
		super();
		this.values = values;
		
	}
	
	public void openIndex(ISourceLocation indexPath) {
		try {
			indexDirectory = FSDirectory.open(new File(indexPath.getPath()).toPath());
			config = new IndexWriterConfig(new StandardAnalyzer());
			indexWriter = new IndexWriter(indexDirectory, config);
		} catch (IOException e) {
			throw RuntimeExceptionFactory.javaException(e, null, null);
		}
	}

	public void closeIndex() {
		try {
			indexWriter.close();
			indexDirectory.close();
		} catch (IOException e) {
			throw RuntimeExceptionFactory.javaException(e, null, null);
		}
	}
	
	public void addDocument(IMap documentValues) {
		try {
			Document doc = new Document();
			StringBuilder allContents = new StringBuilder();
			for (IValue key : documentValues) {
				IString keyAsString = (IString)key;
				if (documentValues.get(key).getType().isString()) {
					IString valueAsString = (IString)documentValues.get(key);
					if (keyAsString.equals("id")) {
						doc.add(new StringField(keyAsString.getValue(), valueAsString.getValue(), Field.Store.YES));
					} else {
						doc.add(new TextField(keyAsString.getValue(), valueAsString.getValue(), Field.Store.YES));
					}
					allContents.append(valueAsString.getValue()).append(" ");
				} 
			}
			doc.add(new TextField("fulltext", allContents.toString(), Field.Store.NO));
			indexWriter.addDocument(doc);
		} catch (IOException e) {
			throw RuntimeExceptionFactory.javaException(e, null, null);
		}
	}
	
	public void prepareQueryEngine(ISourceLocation indexPath) {
		try {
			searcher = new IndexSearcher(DirectoryReader.open(FSDirectory.open(new File(indexPath.getPath()).toPath())));
			parser = new QueryParser("fulltext", new StandardAnalyzer());
		} catch (IOException e) {
			throw RuntimeExceptionFactory.javaException(e, null, null);
		}
	}
	
	public IList runQuery(IString queryString) {
		try {
			Query query = parser.parse(queryString.getValue());
			TopDocs topDocs = searcher.search(query, 50);
			ScoreDoc[] hits = topDocs.scoreDocs;
			IListWriter lw = values.listWriter();
			for (int idx = 0; idx < hits.length; ++idx) {
				Document doc = searcher.doc(hits[idx].doc);
				lw.append(values.string(doc.getField("id").stringValue()));
			}
			return lw.done();
		} catch (ParseException e) {
			throw RuntimeExceptionFactory.javaException(e, null, null);
		} catch (IOException e) {
			throw RuntimeExceptionFactory.javaException(e, null, null);
		}
	}
}
