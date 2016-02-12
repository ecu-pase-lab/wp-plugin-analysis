module lang::php::textsearch::Lucene

@javaClass{org.rascalmpl.library.lucene.Lucene}
public java void openIndex(loc indexPath);

@javaClass{org.rascalmpl.library.lucene.Lucene}
public java void closeIndex();

@javaClass{org.rascalmpl.library.lucene.Lucene}
public java void addDocument(map[str,value] properties);

@javaClass{org.rascalmpl.library.lucene.Lucene}
public java void prepareQueryEngine(loc indexPath);

@javaClass{org.rascalmpl.library.lucene.Lucene}
public java list[str] runQuery(str query);
