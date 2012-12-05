-- Import the table data from the data files using the fast COPY method.
\copy users FROM 'users.txt'
\copy nodes FROM 'nodes.txt'
\copy ways FROM 'ways.txt'
\copy relations FROM 'relations.txt'
\copy relation_members FROM 'relation_members.txt'
