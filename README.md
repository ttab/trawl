trawl & tickle
==============

## Make test data

```
spix-dev01$ ./trawl http://spix-bildbank01:9200/images/sgb
Dumping 50 most recent entries. After that every 500th.
Saving mapping
Trawling through posts
  trawling [=======================================] 100% (44002/44002)
Downloading assets
    assets [=======================================] 100% (720/720)
Compressing
  archiving [=======================================] 100% (722/722)
Written 265366585 bytes: /home/martin/trawl/target/images_sgb.zip
Done.
```

## Usage

`traw` will dump all most recent records up to a point, then every nth
to the end. This is so we get both nice recent data as well as some
historic.

* `-r --recent` The number of recent records, defaults to 50.
* `-n --nth` After recent records, grab every nth, defaults to 500.
* `-m --max` Max number of records *to consider*. Default to 0 for all records in the index.

### Example

`-r 100 -n 1000 -m 5000` means download the first 100 records, then
ever 1000th up until the 5000 record in the index. I.e. if there are more than 5000 records
in the index we will end up with 100 + 4 = 104 records in total.

## Upload test data to nexus

```
$ mvn deploy
...
Uploaded: http://spix-core01.driften.net/nexus/content/repositories/snapshots/se/prb/scanpix-trawl/1.0.0-SNAPSHOT/scanpix-trawl-1.0.0-20130618.064742-3-dist.zip (259148 KB at 7650.1 KB/sec)
```

*Notice that pom.xml got a hard coded value for the .zip to deploy to nexus*

```
spix-dev01$ grep images_sgb pom.xml
                <file>target/images_sgb.zip</file>
```
